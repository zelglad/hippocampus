#!/bin/bash
# relaunch Claude desktop app if it's not running.
# launchd fires this every 60s - handles crashes automatically.

if ! pgrep -f "Claude.app/Contents/MacOS/Claude" > /dev/null 2>&1; then
  open -a "Claude"
fi
