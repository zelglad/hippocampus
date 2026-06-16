#!/bin/bash
# one-time migration from the earlier ad-hoc setup to brain-kit paths.
# copies the session cookie and the sync cursor so the fetcher does not re-pull everything,
# then points you at decommissioning the old jobs. safe to run before install.sh.
set -uo pipefail

OLD="$HOME/.config/claude-chat-fetch"
NEW="$HOME/.config/brain-kit"

mkdir -p "$NEW"
if [ -f "$OLD/session.key" ]; then
  cp "$OLD/session.key" "$NEW/session.key" && chmod 600 "$NEW/session.key"
  echo "migrated session.key"
fi
if [ -f "$OLD/state.json" ]; then
  cp "$OLD/state.json" "$NEW/state.json"
  echo "migrated state.json (sync cursor preserved)"
fi

echo
echo "next: run ./install.sh (it will keep the migrated key + cursor), then decommission the old setup:"
echo "  launchctl bootout gui/\$(id -u)/com.claude.memory-consolidation"
echo "  rm ~/Library/LaunchAgents/com.claude.memory-consolidation.plist"
echo "  rm ~/.local/bin/claude-chat-sync.sh ~/.local/bin/fetch_chats.py ~/.local/bin/claude-brain-start.sh"
echo "  rm ~/Library/LaunchAgents/com.claude.brain.plist   # superseded, not loaded"
