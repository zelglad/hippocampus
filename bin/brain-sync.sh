#!/bin/bash
# nightly second-brain pipeline: fetch claude.ai chats, capture local sessions, consolidate.
# runs headless from launchd. all paths come from config - nothing user-specific here.
set -uo pipefail

CONFIG="$HOME/.config/brain-kit/config.env"
LOG="$HOME/.config/brain-kit/sync.log"
LIB="$HOME/.local/share/brain-kit"
PY="$(command -v python3)"

# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

echo "=== brain-sync $(date) ===" >> "$LOG"

# 1. fetch new claude.ai conversations into chats/_inbox
"$PY" "$LIB/fetch_chats.py" >> "$LOG" 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
  # session cookie expired - notify and stop (nothing reliable to ingest)
  osascript -e 'display notification "claude.ai session expired - run: brain-kit setkey" with title "Brain sync"' 2>/dev/null
  echo "auth expired, aborting run" >> "$LOG"
  exit 2
fi

# 2. capture local claude code / remote-control sessions (best-effort, never fatal)
if [ "${BRAIN_CAPTURE_CODE_SESSIONS:-1}" = "1" ]; then
  "$PY" "$LIB/sessions_export.py" >> "$LOG" 2>&1 || echo "sessions export skipped" >> "$LOG"
fi

# 3. consolidate, restricted to the vault and auto-approving only within it.
#    acceptEdits scopes auto-approval to the working directory; the shipped
#    vault settings add the sandbox + deny rules that block reads of secrets.
if [ -z "${BRAIN_VAULT:-}" ] || [ ! -d "$BRAIN_VAULT" ]; then
  echo "BRAIN_VAULT missing or not a directory: ${BRAIN_VAULT:-unset}" >> "$LOG"
  exit 1
fi
cd "$BRAIN_VAULT" || { echo "cannot cd to vault" >> "$LOG"; exit 1; }
"${BRAIN_CLAUDE_BIN:-claude}" -p "/consolidate-brain" --permission-mode acceptEdits >> "$LOG" 2>&1

echo "=== done $(date) ===" >> "$LOG"
