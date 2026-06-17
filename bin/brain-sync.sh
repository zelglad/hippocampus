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

SENTINEL="${BRAIN_VAULT:-}/chats/_sync-status.md"

write_status() {
  # writes last-run status into the vault so Obsidian shows it on any device
  local status="$1"
  printf 'last_run: %s\nstatus: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" > "$SENTINEL" 2>/dev/null || true
}

echo "=== brain-sync $(date) ===" >> "$LOG"

# 1. fetch new claude.ai conversations into chats/_inbox
"$PY" "$LIB/fetch_chats.py" >> "$LOG" 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "auth expired - attempting auto-refresh from Claude app cookies..." >> "$LOG"
  "$PY" "$LIB/refresh_session_key.py" >> "$LOG" 2>&1
  refresh_rc=$?
  if [ "$refresh_rc" -eq 0 ]; then
    echo "session key refreshed, retrying fetch..." >> "$LOG"
    "$PY" "$LIB/fetch_chats.py" >> "$LOG" 2>&1
    rc=$?
  fi
  if [ "$rc" -eq 2 ]; then
    osascript -e 'display notification "claude.ai session expired and auto-refresh failed - run: brain-kit setkey" with title "Brain sync"' 2>/dev/null
    echo "auth still expired after refresh attempt, aborting" >> "$LOG"
    write_status "AUTH EXPIRED - auto-refresh failed, run: brain-kit setkey"
    exit 2
  fi
fi
if [ "$rc" -ne 0 ]; then
  echo "fetch failed (rc=$rc), aborting run" >> "$LOG"
  write_status "FETCH FAILED (rc=$rc) - check sync.log"
  exit "$rc"
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
  write_status "CONFIG ERROR - BRAIN_VAULT missing"
  exit 1
fi
cd "$BRAIN_VAULT" || { echo "cannot cd to vault" >> "$LOG"; write_status "ERROR - cannot cd to vault"; exit 1; }
"${BRAIN_CLAUDE_BIN:-claude}" -p "/consolidate-brain" --permission-mode acceptEdits >> "$LOG" 2>&1
claude_rc=$?

if [ "$claude_rc" -ne 0 ]; then
  echo "consolidation failed (rc=$claude_rc)" >> "$LOG"
  osascript -e "display notification \"consolidation failed (rc=$claude_rc)\" with title \"Brain sync\"" 2>/dev/null
  write_status "CONSOLIDATION FAILED (rc=$claude_rc) - check sync.log"
  exit "$claude_rc"
fi

write_status "OK"
echo "=== done $(date) ===" >> "$LOG"
