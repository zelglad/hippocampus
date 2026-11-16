#!/bin/bash
# watchdog for the visible-terminal remote-control session.
# launchd runs this on login and every 30s; if no remote-control session is up,
# it opens a Terminal window running one. you see every request live, and it self-heals.
# the session cds into the vault and uses acceptEdits, so it is restricted to the vault.
# --spawn=session = single-session mode: the host Terminal IS the session you drive from
# the phone, so commands sent from the phone render live in this window. it exits when that
# session ends, and the watchdog reopens a fresh one.
#
# failure handling: a session that dies within HEALTHY_SECS of launch (e.g. the bridge
# registration timeout) counts as a failure. consecutive failures back off exponentially
# (60s, 2m, 4m ... capped at MAX_BACKOFF) instead of opening a window every 30s, and the
# window closes itself when the session exits so dead shells don't pile up.
CONFIG="$HOME/.config/brain-kit/config.env"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

LABEL="${BRAIN_LABEL:-brain}"
VAULT="${BRAIN_VAULT:-$HOME}"
CLAUDE="${BRAIN_CLAUDE_BIN:-claude}"
STATE="${BRAIN_RT_STATE:-$HOME/.config/brain-kit/remote-terminal.state}"

GRACE_SECS=60        # never relaunch sooner than this after a launch (avoids "already served" races)
HEALTHY_SECS=120     # a session that stayed up this long resets the failure count
MAX_BACKOFF=1800     # cap between retries while failing
ALERT_AFTER=5        # telegram ping after this many consecutive failures

now=$(date +%s)

# load state: last_launch, last_up, fails, alerted
last_launch=0; last_up=0; fails=0; alerted=0
# shellcheck disable=SC1090
[ -f "$STATE" ] && . "$STATE"

save_state() {
  # rewrite the whole state file in one go
  printf 'last_launch=%s\nlast_up=%s\nfails=%s\nalerted=%s\n' \
    "$last_launch" "$last_up" "$fails" "$alerted" > "$STATE" 2>/dev/null || true
}

notify() {
  # optional telegram ping, same config vars as brain-sync.sh; no-op without them
  [ -n "${BRAIN_TELEGRAM_TOKEN:-}" ] && [ -n "${BRAIN_TELEGRAM_CHAT_ID:-}" ] || return 0
  # url goes in via stdin so the token never shows up in the process list
  printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$BRAIN_TELEGRAM_TOKEN" \
    | curl -s -m 15 -K - \
        --data-urlencode "chat_id=$BRAIN_TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$1" \
        >/dev/null 2>&1 || true
}

# already running? record that it's alive and stop
if pgrep -f "remote-control --name $LABEL" > /dev/null 2>&1; then
  last_up=$now
  # a session that has been up long enough clears the failure streak
  if [ "$last_launch" -gt 0 ] && [ $((now - last_launch)) -ge "$HEALTHY_SECS" ] && [ "$fails" -gt 0 ]; then
    [ "$alerted" -eq 1 ] && notify "Hippocampus remote-control recovered after $fails failed starts"
    fails=0; alerted=0
  fi
  save_state
  exit 0
fi

# not running: did the previous launch die before it became healthy?
next_fails=0
if [ "$last_launch" -gt 0 ] && [ $((last_up - last_launch)) -lt "$HEALTHY_SECS" ]; then
  next_fails=$((fails + 1))
fi

# wait = grace on a clean restart, exponential backoff while failing
wait=$GRACE_SECS
if [ "$next_fails" -gt 0 ]; then
  # clamp the exponent so the shift can't overflow on a long streak
  shift_by=$((next_fails - 1)); [ "$shift_by" -gt 10 ] && shift_by=10
  wait=$((GRACE_SECS << shift_by))
  [ "$wait" -gt "$MAX_BACKOFF" ] && wait=$MAX_BACKOFF
fi
if [ $((now - last_launch)) -lt "$wait" ]; then
  exit 0
fi

fails=$next_fails
[ "$fails" -eq 0 ] && alerted=0
if [ "$fails" -ge "$ALERT_AFTER" ] && [ "$alerted" -eq 0 ]; then
  notify "Hippocampus remote-control failed to start $fails times in a row; retrying every ~$((MAX_BACKOFF / 60))m max. Check ~/.config/brain-kit/remote-terminal.log"
  alerted=1
fi
last_launch=$now
last_up=0
save_state

echo "$(date '+%F %T') launching (consecutive failures: $fails)"
# "; exit 0" makes the shell exit cleanly when claude does, so Terminal closes the window
osascript -e "tell application \"Terminal\" to do script \"cd '$VAULT' && '$CLAUDE' remote-control --name '$LABEL' --permission-mode acceptEdits --spawn=session; exit 0\"" 2>/dev/null
