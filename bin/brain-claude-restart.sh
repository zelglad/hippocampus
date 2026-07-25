#!/bin/bash
# graceful daily restart so Claude picks up any pending update.
# runs at 4 AM via launchd, one hour after the 3 AM brain-sync.
# electron apps check for updates and apply them on next launch.

# force-kill directly: a polite "tell app to quit" blocks forever if the
# app is unresponsive, so the pkill fallback never gets a chance to fire.
pkill -9 -f "Claude.app/Contents/MacOS/Claude" 2>/dev/null || true
sleep 5
open -a "Claude"
