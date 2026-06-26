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
import shutil
import sqlite3
import plistlib
import tempfile
import urllib.request
import urllib.error
from datetime import datetime, timezone

# decrypt helpers live alongside this file in refresh_session_key.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from refresh_session_key import _get_keychain_password, _derive_key, _decrypt_cookie

CONFIG_DIR = os.path.expanduser("~/.config/brain-kit")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.env")
KEY_FILE = os.path.join(CONFIG_DIR, "session.key")
STATE_FILE = os.path.join(CONFIG_DIR, "state.json")
COOKIE_DB = os.path.expanduser("~/Library/Application Support/Claude/Cookies")
CLAUDE_APP = "/Applications/Claude.app"

BASE = "https://claude.ai/api"
# claude.ai sits behind a cloudflare managed challenge. a bare sessionKey gets a
# 403 "just a moment" page; only the full cookie jar (incl. cf_clearance/__cf_bm)
# sent with the claude app's real electron user-agent clears it. cf_clearance is
# bound to that exact UA, so we derive it from the installed app to track updates.
_UA_FALLBACK = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Claude/1.15962.0 Chrome/148.0.7778.254 "
                "Electron/42.4.0 Safari/537.36")


def build_ua():
    # reconstruct the claude desktop app's electron user-agent from the installed
    # bundle. cf_clearance only validates against the UA that solved the challenge.
    try:
        with open(os.path.join(CLAUDE_APP, "Contents/Info.plist"), "rb") as f:
            claude_ver = plistlib.load(f).get("CFBundleShortVersionString", "")
        fw = os.path.join(CLAUDE_APP,
                          "Contents/Frameworks/Electron Framework.framework/Electron Framework")
        chrome_electron = ""
        with open(fw, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                m = re.search(rb"Chrome/[\d.]+ Electron/[\d.]+", chunk)
                if m:
                    chrome_electron = m.group().decode()
                    break
        if claude_ver and chrome_electron:
            return ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                    f"(KHTML, like Gecko) Claude/{claude_ver} {chrome_electron} Safari/537.36")
    except Exception:
        pass
    return _UA_FALLBACK


UA = build_ua()


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


def read_cookie_jar():
    # decrypt every claude.ai cookie from the desktop app's store into a Cookie
    # header. cf_clearance + __cf_bm here are what clear the cloudflare challenge;
    # sessionKey alone is not enough.
    if not os.path.exists(COOKIE_DB):
        print(f"no Claude cookie db at {COOKIE_DB}", file=sys.stderr)
        sys.exit(3)
    pw = _get_keychain_password()
    if not pw:
        print("Claude Safe Storage keychain entry not found", file=sys.stderr)
        sys.exit(3)
    aes = _derive_key(pw)
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as t:
        shutil.copy2(COOKIE_DB, t.name)
        tmp = t.name
    try:
        conn = sqlite3.connect(tmp)
        rows = conn.execute(
            "SELECT name, encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai'"
        ).fetchall()
        conn.close()
    finally:
        os.unlink(tmp)
    jar = {}
    for name, enc in rows:
        val = _decrypt_cookie(enc, aes)
        if val is not None:
            jar[name] = val.decode("utf-8", "replace")
    if "sessionKey" not in jar:
        print("sessionKey not found in Claude cookie db", file=sys.stderr)
        sys.exit(3)
    return "; ".join(f"{k}={v}" for k, v in jar.items())


def http_get(path, cookie_hdr):
    # GET a claude.ai api path and return parsed json
    url = path if path.startswith("http") else BASE + path
    req = urllib.request.Request(url)
    req.add_header("Cookie", cookie_hdr)
    req.add_header("User-Agent", UA)
    req.add_header("Accept", "application/json")
    req.add_header("Accept-Encoding", "gzip, identity")
    try:
        resp = urllib.request.urlopen(req, timeout=60)
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            # 403 here is usually a cloudflare challenge, not an expired key - we
            # send the full cookie jar (cf_clearance/__cf_bm) + the app's electron
            # UA to clear it. check the Claude app is running/recently active.
            print(f"auth failed ({e.code}) - cloudflare challenge or stale cookie jar; "
                  "ensure Claude app is running", file=sys.stderr)
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
    safe_name = name.replace('"', "'")
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
    cookie_hdr = read_cookie_jar()
    state = load_state()
    last_sync = parse_ts(state.get("last_sync"))

    orgs = http_get("/organizations", cookie_hdr)
    if not isinstance(orgs, list) or not orgs:
        print("no organizations returned", file=sys.stderr)
        sys.exit(1)
    org = orgs[0].get("uuid")

    conversations = http_get(f"/organizations/{org}/chat_conversations", cookie_hdr)
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
            cookie_hdr,
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
