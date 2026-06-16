#!/bin/bash
# watchdog for the visible-terminal remote-control session.
# launchd runs this on login and every 30s; if no remote-control session is up,
# it opens a Terminal window running one. you see every request live, and it self-heals.
# the session cds into the vault and uses acceptEdits, so it is restricted to the vault.
CONFIG="$HOME/.config/brain-kit/config.env"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

LABEL="${BRAIN_LABEL:-brain}"
VAULT="${BRAIN_VAULT:-$HOME}"
CLAUDE="${BRAIN_CLAUDE_BIN:-claude}"

# already running? nothing to do
if pgrep -f "remote-control --name $LABEL" > /dev/null 2>&1; then
  exit 0
fi

osascript -e "tell application \"Terminal\" to do script \"cd '$VAULT' && '$CLAUDE' remote-control --name '$LABEL' --permission-mode acceptEdits\"" 2>/dev/null
