#!/usr/bin/env python3
# best-effort capture of local Claude Code / remote-control sessions into the vault.
# these sessions live in ~/.claude/projects/**/*.jsonl and never hit the claude.ai api,
# so the chat fetcher is blind to them - this closes that gap.
# tolerant by design: any parse error on a line or file is skipped, never fatal.
# stdlib only. exit 0 always (so it can never break the nightly run).

import json
import os
import sys
import glob
from datetime import datetime, timezone

CONFIG_DIR = os.path.expanduser("~/.config/brain-kit")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.env")
STATE_FILE = os.path.join(CONFIG_DIR, "sessions_state.json")
PROJECTS = os.path.expanduser("~/.claude/projects")


def load_vault():
    cfg = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    cfg[k.strip()] = v.strip().strip('"').strip("'")
    vault = os.environ.get("BRAIN_VAULT") or cfg.get("BRAIN_VAULT")
    return os.path.expanduser(vault) if vault else None


def load_cursor():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE) as f:
                return json.load(f).get("mtime", 0)
        except Exception:
            return 0
    return 0


def save_cursor(mtime):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump({"mtime": mtime}, f)


def extract_text(obj):
    # pull readable text out of one transcript event, tolerant of shape changes
    msg = obj.get("message") if isinstance(obj.get("message"), dict) else obj
    role = msg.get("role") or obj.get("type") or ""
    content = msg.get("content")
    text = ""
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                parts.append(b.get("text", ""))
        text = "\n\n".join(p for p in parts if p)
    return role, text.strip()


def render(path):
    # render one .jsonl session into markdown; return None if nothing usable
    rows = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                role, text = extract_text(obj)
                if text and role in ("user", "assistant", "human"):
                    who = "Human" if role in ("user", "human") else "Assistant"
                    rows.append((who, text))
    except Exception:
        return None
    if not rows:
        return None
    out = ["---", "source: claude-code-session", f"file: {os.path.basename(path)}",
           f"captured_at: {datetime.now(timezone.utc).isoformat()}", "---", ""]
    for who, text in rows:
        out.append(f"### {who}")
        out.append("")
        out.append(text)
        out.append("")
    return "\n".join(out)


def main():
    vault = load_vault()
    if not vault or not os.path.isdir(PROJECTS):
        return
    out_dir = os.path.join(vault, "sessions")
    os.makedirs(out_dir, exist_ok=True)
    cursor = load_cursor()
    newest = cursor
    count = 0
    for path in glob.glob(os.path.join(PROJECTS, "**", "*.jsonl"), recursive=True):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime <= cursor:
            continue
        md = render(path)
        if md:
            base = os.path.splitext(os.path.basename(path))[0]
            with open(os.path.join(out_dir, f"{base}.md"), "w") as f:
                f.write(md)
            count += 1
        newest = max(newest, mtime)
    save_cursor(newest)
    print(f"captured {count} local session(s) into {out_dir}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # never fail the nightly run over session capture
        print(f"sessions export skipped: {e}", file=sys.stderr)
    sys.exit(0)
