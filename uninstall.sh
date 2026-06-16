#!/bin/bash
# removes the launchd jobs and installed scripts. leaves your vault and config untouched
# unless you pass --purge (which also deletes ~/.config/brain-kit, including the cookie).
set -uo pipefail
UID_NUM="$(id -u)"
AGENTS="$HOME/Library/LaunchAgents"

for label in com.brain.sync com.brain.remote; do
  launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null
  rm -f "$AGENTS/$label.plist"
done
rm -rf "$HOME/.local/share/brain-kit"
rm -rf "$HOME/.claude/skills/consolidate-brain"
echo "removed launchd jobs, scripts, and skill."

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/brain-kit"
  echo "purged ~/.config/brain-kit (config + cookie + state)."
else
  echo "left ~/.config/brain-kit in place (run with --purge to remove it)."
fi
echo "note: vault security settings in <vault>/.claude/settings.json were left as-is."
