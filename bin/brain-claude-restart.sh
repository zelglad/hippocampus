#!/bin/bash
# graceful daily restart so Claude picks up any pending update.
# runs at 3 AM via launchd, well before the 4:18 AM brain-sync.
# electron apps check for updates and apply them on next launch.

osascript -e 'tell application "Claude" to quit' 2>/dev/null \
  || pkill -f "Claude.app/Contents/MacOS/Claude" 2>/dev/null \
  || true

sleep 15
open -a "Claude"
