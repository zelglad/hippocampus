#!/bin/bash
# idempotent installer for brain-kit. safe to re-run.
# reproduces the whole second-brain pipeline on a fresh mac. asks for the few
# machine-specific things (vault path, claude binary) and never stores secrets in the repo.
# the claude.ai session key is extracted automatically from the Claude desktop app.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_DIR="$HOME/.config/brain-kit"
LIB_DIR="$HOME/.local/share/brain-kit"
SKILL_DIR="$HOME/.claude/skills/consolidate-brain"
AGENTS="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"

say() { printf "\n\033[1m%s\033[0m\n" "$1"; }
ask() { local p="$1" d="$2" a; read -r -p "$p [$d]: " a; echo "${a:-$d}"; }

say "brain-kit installer"

# --- 1. gather machine-specific values ---
DEFAULT_CLAUDE="$(command -v claude || echo "$HOME/.local/bin/claude")"
VAULT="$(ask "Absolute path to your Obsidian vault" "$HOME/Documents/brain")"
VAULT="${VAULT/#\~/$HOME}"
CLAUDE_BIN="$(ask "Path to the claude binary" "$DEFAULT_CLAUDE")"
LABEL="$(ask "Remote-control session name" "brain")"
HOUR="$(ask "Nightly sync hour (0-23)" "3")"
MIN="$(ask "Nightly sync minute (0-59)" "0")"

if [ ! -d "$VAULT" ]; then
  echo "warning: vault path does not exist yet: $VAULT"
  read -r -p "create it? [y/N]: " mk
  [ "$mk" = "y" ] && mkdir -p "$VAULT"
fi

# --- 2. config dir + config.env (no secrets) ---
say "writing config"
mkdir -p "$CFG_DIR"
cat > "$CFG_DIR/config.env" <<EOF
BRAIN_VAULT="$VAULT"
BRAIN_CLAUDE_BIN="$CLAUDE_BIN"
BRAIN_LABEL="$LABEL"
BRAIN_SYNC_HOUR=$HOUR
BRAIN_SYNC_MINUTE=$MIN
BRAIN_CAPTURE_CODE_SESSIONS=1
EOF

# --- 3. install scripts ---
say "installing scripts to $LIB_DIR"
mkdir -p "$LIB_DIR"
cp "$REPO/bin/fetch_chats.py" \
   "$REPO/bin/sessions_export.py" \
   "$REPO/bin/brain-sync.sh" \
   "$REPO/bin/refresh_session_key.py" \
   "$REPO/bin/brain-claude-watchdog.sh" \
   "$REPO/bin/brain-claude-restart.sh" \
   "$LIB_DIR/"
chmod +x "$LIB_DIR/"*.sh "$LIB_DIR/"*.py

# --- 4. session cookie (auto-extracted from Claude desktop app) ---
say "claude.ai session key"
touch "$CFG_DIR/sync.log"
if python3 "$LIB_DIR/refresh_session_key.py" 2>/dev/null; then
  echo "session key extracted from Claude desktop app automatically."
elif [ ! -s "$CFG_DIR/session.key" ] || grep -q "^#" "$CFG_DIR/session.key" 2>/dev/null; then
  echo "Claude desktop app not available. Open and sign in to the Claude app, then run:"
  echo "  python3 $LIB_DIR/refresh_session_key.py"
  echo "Or paste your sessionKey manually (from claude.ai DevTools > Application > Cookies):"
  read -r -p "sessionKey (or leave blank to do later): " KEY
  if [ -n "$KEY" ]; then
    printf "%s" "$KEY" > "$CFG_DIR/session.key"
    chmod 600 "$CFG_DIR/session.key"
  fi
else
  echo "session key already set."
fi

# --- 5. install the consolidation skill (user scope, available everywhere) ---
say "installing consolidate-brain skill"
mkdir -p "$SKILL_DIR"
cp "$REPO/skills/consolidate-brain/SKILL.md" "$SKILL_DIR/"

# --- 6. merge security settings into the vault's project settings ---
say "applying sandbox + permission settings to the vault"
mkdir -p "$VAULT/.claude"
python3 - "$REPO/templates/settings.brain.json" "$VAULT/.claude/settings.json" <<'PY'
import json, sys
tmpl, target = sys.argv[1], sys.argv[2]
add = json.load(open(tmpl))
try:
    cur = json.load(open(target))
except Exception:
    cur = {}
# merge permissions (defaultMode + dedup deny list) and sandbox without clobbering other keys
perm = cur.setdefault("permissions", {})
perm["defaultMode"] = add["permissions"]["defaultMode"]
deny = perm.setdefault("deny", [])
for r in add["permissions"]["deny"]:
    if r not in deny:
        deny.append(r)
sb = cur.setdefault("sandbox", {})
sb["enabled"] = True
fs = sb.setdefault("filesystem", {})
dr = fs.setdefault("denyRead", [])
for p in add["sandbox"]["filesystem"]["denyRead"]:
    if p not in dr:
        dr.append(p)
ex = sb.setdefault("excludedCommands", [])
for c in add["sandbox"]["excludedCommands"]:
    if c not in ex:
        ex.append(c)
json.dump(cur, open(target, "w"), indent=2)
print("merged ->", target)
PY

# --- 7. generate + load launchd jobs ---
say "installing launchd jobs"
mkdir -p "$AGENTS"
load_plist() {
  local label="$1" plist="$AGENTS/$1.plist"
  launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null
  launchctl bootstrap "gui/$UID_NUM" "$plist" 2>/dev/null \
    || launchctl load "$plist" 2>/dev/null
}
# nightly sync
sed -e "s|__HOME__|$HOME|g" -e "s|__HOUR__|$HOUR|g" -e "s|__MIN__|$MIN|g" \
  "$REPO/templates/com.brain.sync.plist.tmpl" > "$AGENTS/com.brain.sync.plist"
load_plist com.brain.sync
echo "nightly sync scheduled for ${HOUR}:${MIN} local"
# claude app watchdog (keeps the app running so session keys stay fresh)
sed -e "s|__HOME__|$HOME|g" \
  "$REPO/templates/com.brain.claude-watchdog.plist.tmpl" > "$AGENTS/com.brain.claude-watchdog.plist"
load_plist com.brain.claude-watchdog
echo "claude app watchdog loaded (60s interval)"
# daily restart at 4 AM (picks up app updates)
sed -e "s|__HOME__|$HOME|g" \
  "$REPO/templates/com.brain.claude-restart.plist.tmpl" > "$AGENTS/com.brain.claude-restart.plist"
load_plist com.brain.claude-restart
echo "claude app restart scheduled for 04:00"

# --- 8. optional remote-control (phone access to vault + local MCP servers) ---
say "remote control (drive the vault + local MCP servers from your phone)"
echo "  1) visible terminal - opens a Terminal window so you watch requests live (self-heals every 30s)"
echo "  2) headless         - no window, instant KeepAlive restart"
echo "  3) none             - synced chats + nightly sync already capture everything"
RC="$(ask "choose" "1")"
copy_remote_script() { cp "$REPO/bin/brain-remote-terminal.sh" "$LIB_DIR/" && chmod +x "$LIB_DIR/brain-remote-terminal.sh"; }
load_agent() { launchctl bootout "gui/$UID_NUM/$1" 2>/dev/null; launchctl bootstrap "gui/$UID_NUM" "$AGENTS/$1.plist" 2>/dev/null || launchctl load "$AGENTS/$1.plist" 2>/dev/null; }
case "$RC" in
  1)
    copy_remote_script
    sed -e "s|__HOME__|$HOME|g" "$REPO/templates/com.brain.remote-terminal.plist.tmpl" > "$AGENTS/com.brain.remote-terminal.plist"
    load_agent com.brain.remote-terminal
    echo "visible-terminal remote loaded - run 'claude' once in the vault first to accept the trust dialog."
    ;;
  2)
    sed -e "s|__HOME__|$HOME|g" -e "s|__CLAUDE_BIN__|$CLAUDE_BIN|g" \
        -e "s|__BRAIN_VAULT__|$VAULT|g" -e "s|__BRAIN_LABEL__|$LABEL|g" \
        "$REPO/templates/com.brain.remote.plist.tmpl" > "$AGENTS/com.brain.remote.plist"
    load_agent com.brain.remote
    echo "headless remote loaded as '$LABEL' - find it in the Claude app under Code."
    ;;
  *)
    echo "skipping remote control."
    ;;
esac

say "done"
echo "test the fetch:      python3 $LIB_DIR/fetch_chats.py"
echo "refresh session key: python3 $LIB_DIR/refresh_session_key.py"
echo "watch the log:       tail -f $CFG_DIR/sync.log"
echo "run sync now:        $LIB_DIR/brain-sync.sh"
