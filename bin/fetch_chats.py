#!/usr/bin/env python3
# fetches new/updated claude.ai conversations into the vault inbox as markdown.
# stdlib only, no pip deps. reads config + the session cookie from ~/.config/brain-kit/.
# nothing here is user-specific: all paths come from config or $HOME.
# exit codes: 0 ok, 2 auth expired (401/403), 3 config/setup problem, 1 other error.

import json
import os
import re
import sys
import gzip
import urllib.request
import urllib.error
from datetime import datetime, timezone

CONFIG_DIR = os.path.expanduser("~/.config/brain-kit")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.env")
KEY_FILE = os.path.join(CONFIG_DIR, "session.key")
STATE_FILE = os.path.join(CONFIG_DIR, "state.json")

BASE = "https://claude.ai/api"
# a normal browser user-agent reduces the odds of a cloudflare challenge
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")


def load_config():
    # read simple KEY="value" lines from config.env; env vars win if set
    cfg = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"').strip("'")
    vault = os.environ.get("BRAIN_VAULT") or cfg.get("BRAIN_VAULT")
    if not vault:
        print("BRAIN_VAULT not set (run install.sh)", file=sys.stderr)
        sys.exit(3)
    return os.path.expanduser(vault)


def read_key():
    # the cookie value, stripped of any whitespace or accidental "sessionKey=" prefix
    if not os.path.exists(KEY_FILE):
        print(f"no session key at {KEY_FILE}", file=sys.stderr)
        sys.exit(3)
    with open(KEY_FILE) as f:
        raw = f.read().strip()
    if raw.startswith("sessionKey="):
        raw = raw.split("=", 1)[1].strip()
    if not raw or raw.startswith("#"):
        print("session key file is empty or still a placeholder", file=sys.stderr)
        sys.exit(3)
    return raw


def http_get(path, key):
    # GET a claude.ai api path and return parsed json
    url = path if path.startswith("http") else BASE + path
    req = urllib.request.Request(url)
    req.add_header("Cookie", f"sessionKey={key}")
    req.add_header("User-Agent", UA)
    req.add_header("Accept", "application/json")
    req.add_header("Accept-Encoding", "gzip, identity")
    try:
        resp = urllib.request.urlopen(req, timeout=60)
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            print(f"auth failed ({e.code}) - session cookie expired or blocked", file=sys.stderr)
            sys.exit(2)
        print(f"http {e.code} on {url}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"network error on {url}: {e}", file=sys.stderr)
        sys.exit(1)
    data = resp.read()
    if resp.headers.get("Content-Encoding") == "gzip":
        data = gzip.decompress(data)
    return json.loads(data.decode("utf-8"))


def load_state():
    # last_sync is an iso timestamp; only conversations updated after it are fetched
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"last_sync": "1970-01-01T00:00:00+00:00"}


def save_state(state):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def parse_ts(s):
    # claude timestamps look like 2026-06-15T12:34:56.789012Z
    if not s:
        return datetime.fromtimestamp(0, tz=timezone.utc)
    s = s.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return datetime.fromtimestamp(0, tz=timezone.utc)


def slugify(name):
    # lowercase, alnum + hyphen, collapsed, capped
    s = (name or "untitled").lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return (s or "untitled")[:60]


def msg_text(m):
    # extract readable text from either the old (text) or new (content blocks) shape
    blocks = m.get("content")
    if isinstance(blocks, list):
        parts = []
        for b in blocks:
            t = b.get("type")
            if t == "text":
                parts.append(b.get("text", ""))
            elif t == "tool_use":
                parts.append(f"_[tool: {b.get('name', '')}]_")
            elif t == "tool_result":
                parts.append("_[tool result]_")
        joined = "\n\n".join(p for p in parts if p)
        if joined:
            return joined
    return m.get("text", "") or ""


def render_markdown(conv):
    # build the per-conversation markdown file content
    uuid = conv.get("uuid", "")
    name = conv.get("name") or "Untitled"
    created = conv.get("created_at", "")
    updated = conv.get("updated_at", "")
    msgs = conv.get("chat_messages") or conv.get("messages") or []
    # order by created_at; branching is rare in normal use
    msgs = sorted(msgs, key=lambda m: parse_ts(m.get("created_at")))

    lines = []
    lines.append("---")
    lines.append(f"uuid: {uuid}")
    safe_name = name.replace('"', "'").replace("\n", " ")
    lines.append(f'name: "{safe_name}"')
    lines.append(f"created_at: {created}")
    lines.append(f"updated_at: {updated}")
    lines.append(f"url: https://claude.ai/chat/{uuid}")
    lines.append("source: claude.ai")
    lines.append(f"fetched_at: {datetime.now(timezone.utc).isoformat()}")
    lines.append("---")
    lines.append("")
    lines.append(f"# {name}")
    lines.append("")
    for m in msgs:
        sender = (m.get("sender") or "").lower()
        who = "Human" if sender == "human" else "Assistant"
        text = msg_text(m).strip()
        if not text:
            continue
        lines.append(f"### {who}")
        lines.append("")
        lines.append(text)
        lines.append("")
    return "\n".join(lines)


def main():
    vault = load_config()
    inbox = os.path.join(vault, "chats", "_inbox")
    key = read_key()
    state = load_state()
    last_sync = parse_ts(state.get("last_sync"))

    orgs = http_get("/organizations", key)
    if not isinstance(orgs, list) or not orgs:
        print("no organizations returned", file=sys.stderr)
        sys.exit(1)
    org = orgs[0].get("uuid")

    conversations = http_get(f"/organizations/{org}/chat_conversations", key)
    if isinstance(conversations, dict):
        conversations = conversations.get("conversations", [])

    os.makedirs(inbox, exist_ok=True)
    fetched = 0
    for c in conversations:
        if parse_ts(c.get("updated_at")) <= last_sync:
            continue
        uuid = c.get("uuid")
        full = http_get(
            f"/organizations/{org}/chat_conversations/{uuid}"
            "?tree=True&rendering_mode=messages&render_all_tools=true",
            key,
        )
        md = render_markdown(full)
        uuid8 = (uuid or "x").split("-")[0]
        fname = f"{uuid8}-{slugify(c.get('name'))}.md"
        with open(os.path.join(inbox, fname), "w") as f:
            f.write(md)
        fetched += 1

    # advance the cursor to now so we never re-pull the same window
    state["last_sync"] = datetime.now(timezone.utc).isoformat()
    save_state(state)
    print(f"fetched {fetched} new/updated conversation(s) into {inbox}")


if __name__ == "__main__":
    main()
