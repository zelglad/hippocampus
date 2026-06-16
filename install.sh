#!/bin/bash
# idempotent installer for brain-kit. safe to re-run.
# reproduces the whole second-brain pipeline on a fresh mac. asks for the few
# machine-specific things (vault path, session cookie) and never stores them in the repo.
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
HOUR="$(ask "Nightly sync hour (0-23)" "4")"
MIN="$(ask "Nightly sync minute (0-59)" "18")"

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

# --- 3. session cookie (prompted, never committed) ---
if [ ! -s "$CFG_DIR/session.key" ] || grep -q "^#" "$CFG_DIR/session.key" 2>/dev/null; then
  say "claude.ai session cookie"
  echo "In a browser logged into claude.ai: DevTools > Application > Cookies > claude.ai > copy the sessionKey value (starts with sk-ant-sid01-)."
  read -r -p "Paste sessionKey (or leave blank to do it later with: ./install.sh setkey): " KEY
  if [ -n "$KEY" ]; then
    printf "%s" "$KEY" > "$CFG_DIR/session.key"
  else
    echo "# paste your sessionKey here, then run: chmod 600 this file" > "$CFG_DIR/session.key"
  fi
fi
chmod 600 "$CFG_DIR/session.key"
touch "$CFG_DIR/sync.log"

# --- 4. install scripts ---
say "installing scripts to $LIB_DIR"
mkdir -p "$LIB_DIR"
cp "$REPO/bin/fetch_chats.py" "$REPO/bin/sessions_export.py" "$REPO/bin/brain-sync.sh" "$LIB_DIR/"
chmod +x "$LIB_DIR/"*.sh "$LIB_DIR/"*.py

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

# --- 7. generate + load the nightly launchd job ---
say "installing nightly launchd job (com.brain.sync)"
mkdir -p "$AGENTS"
sed -e "s|__HOME__|$HOME|g" -e "s|__HOUR__|$HOUR|g" -e "s|__MIN__|$MIN|g" \
  "$REPO/templates/com.brain.sync.plist.tmpl" > "$AGENTS/com.brain.sync.plist"
launchctl bootout "gui/$UID_NUM/com.brain.sync" 2>/dev/null
launchctl bootstrap "gui/$UID_NUM" "$AGENTS/com.brain.sync.plist" 2>/dev/null \
  || launchctl load "$AGENTS/com.brain.sync.plist" 2>/dev/null
echo "nightly sync scheduled for ${HOUR}:${MIN} local"

# --- 8. optional remote-control job (phone access to vault + local MCP servers) ---
read -r -p $'\nInstall the optional remote-control job for phone access? [y/N]: ' rc
if [ "$rc" = "y" ]; then
  sed -e "s|__HOME__|$HOME|g" -e "s|__CLAUDE_BIN__|$CLAUDE_BIN|g" \
      -e "s|__BRAIN_VAULT__|$VAULT|g" -e "s|__BRAIN_LABEL__|$LABEL|g" \
      "$REPO/templates/com.brain.remote.plist.tmpl" > "$AGENTS/com.brain.remote.plist"
  launchctl bootout "gui/$UID_NUM/com.brain.remote" 2>/dev/null
  launchctl bootstrap "gui/$UID_NUM" "$AGENTS/com.brain.remote.plist" 2>/dev/null \
    || launchctl load "$AGENTS/com.brain.remote.plist" 2>/dev/null
  echo "remote-control loaded as '$LABEL' - first run 'claude' once in the vault to accept the trust dialog, then find it in the Claude app under Code."
fi

say "done"
echo "test the fetch now:  python3 $LIB_DIR/fetch_chats.py"
echo "watch the log:       tail -f $CFG_DIR/sync.log"
echo "update the cookie:   edit $CFG_DIR/session.key (chmod 600)"
