# brain-kit · v0.1.1

Turn Claude into a self-maintaining "second brain." A nightly job pulls all your
claude.ai conversations into an Obsidian vault, captures your local Claude Code
sessions too, and uses a Claude skill to fold everything into your notes - then
archives the raw chats losslessly. One command sets the whole thing up on a fresh Mac.

It works because Anthropic already syncs your claude.ai chats across devices.
brain-kit reads them through the claude.ai web API, so you just chat normally on
any device and your brain updates itself overnight.

## What's in the box

| Path | What it is |
|---|---|
| `bin/fetch_chats.py` | Pulls new/updated claude.ai chats into `chats/_inbox/`. stdlib only, no deps. |
| `bin/sessions_export.py` | Best-effort capture of local Claude Code / remote-control sessions (which never hit the claude.ai API) into `sessions/`. |
| `bin/brain-sync.sh` | The nightly wrapper: fetch, capture, then consolidate. Auto-refreshes the session key on auth failure and writes a status sentinel the vault can display on any device. |
| `bin/refresh_session_key.py` | Decrypts the claude.ai `sessionKey` cookie directly from the Claude desktop app's local cookie store. No browser DevTools required - runs automatically on auth failure. |
| `bin/brain-claude-watchdog.sh` | Relaunches the Claude desktop app if it crashes (60s launchd interval). Keeps the cookie store live so auto-refresh always works. |
| `bin/brain-claude-restart.sh` | Graceful daily restart of the Claude desktop app at 4 AM so it picks up auto-updates after the nightly sync. |
| `skills/consolidate-brain/SKILL.md` | The Claude skill that does the actual ingestion with judgment. |
| `templates/` | launchd job templates + security settings, with placeholders the installer fills in. |
| `bin/brain-remote-terminal.sh` | Watchdog for the optional visible-terminal remote-control session. |
| `install.sh` / `uninstall.sh` | Idempotent setup / teardown. |

Remote control (optional, for phone access to the vault + local MCP servers) comes
in two forms the installer offers: a **visible terminal** (a Terminal window you can
watch, self-healing every 30s) or **headless** (no window, instant KeepAlive restart).
Both run in `acceptEdits` cd'd into the vault, so they're path-restricted too.

The split is deliberate: **deterministic work (fetching, file moves) is plain
Python; work that needs judgment (what to keep, where it goes) is a Claude skill;
setup is a shell installer.** Don't collapse these into one thing.

## Prerequisites

Two things must be done once before running the installer:

1. **Claude desktop app** - install from [claude.ai/download](https://claude.ai/download) and sign in. The app stores an encrypted session cookie locally; `refresh_session_key.py` reads it from there. The app must stay running after install (the watchdog handles this automatically).

2. **Claude CLI** - install via `npm install -g @anthropic-ai/claude-code` (or however your org distributes it) and run `claude` once in a terminal to complete authentication. The nightly sync calls `claude -p "/consolidate-brain"` to run the consolidation skill - this is what actually writes to your vault.

Both need a Pro or Team subscription on the same account.

## Install

```bash
git clone <this-repo> brain-kit
cd brain-kit
./install.sh
```

The installer asks for: your vault path, the `claude` binary path, a session name,
and the sync time. It then writes config to `~/.config/brain-kit/`, installs all
scripts and the skill, applies the security settings to your vault, and schedules
three launchd jobs (nightly sync, Claude app watchdog, daily restart). Re-running
it is safe.

The **claude.ai session key** is extracted automatically from the Claude desktop
app's local cookie store - no DevTools required. The installer runs
`refresh_session_key.py` once at install time, and `brain-sync.sh` calls it
automatically whenever the key expires. The key is stored at
`~/.config/brain-kit/session.key` with `600` permissions and is never committed.
The only requirement is that the Claude desktop app is installed and signed in.

The **Claude desktop app must keep running** for the auto-refresh to work. The
watchdog launchd job handles this - if the app crashes or is quit, it relaunches
within 60 seconds. The daily restart at 4 AM ensures the app picks up any pending
automatic updates after the nightly sync fires.

## Security model

This is the part to understand before pointing Claude at your files.

- **Restricted to one path.** The consolidation runs with the vault as its working
  directory and uses `acceptEdits` mode, which auto-approves edits and common file
  commands **only inside the working directory**. Anything outside that scope
  prompts - and in the headless nightly run, a prompt means it aborts rather than
  escaping. It is never run with `bypassPermissions`.
- **Auto-approve within that path.** Inside the vault you get no per-command prompts,
  so the nightly job runs unattended and you can drive it freely from your phone.
- **Secrets are blocked even though reads are broad.** `acceptEdits` auto-approves
  *reads* anywhere, so the shipped vault settings add `deny` rules and a sandbox
  `denyRead` list that block `~/.ssh`, `~/.aws`, `~/.gnupg`, the brain-kit cookie,
  and common key/`.env`/credential files. The Bash sandbox (`sandbox.enabled`)
  additionally confines any shell subprocess to the vault at the OS level.
- **The cookie never leaves your machine and never enters git** (`.gitignore`
  covers `session.key`, `config.env`, state files, and logs).

These settings land in `<vault>/.claude/settings.json` (project scope), so they
travel with the vault and don't touch your global Claude config.

## Sharing with others

This repo is safe to publish: it contains no paths, usernames, or secrets - only
placeholders the installer fills in per machine. To share with specific people:

1. Push to a private repo on GitHub or GitLab.
2. They clone, run `./install.sh`, sign into the Claude desktop app, and the
   session key extracts itself. Nothing of yours is baked in.

## Reproduce on a new Mac

Install prerequisites (`brew install python@3.13` if you want a pinned Python; the
scripts only use stdlib so any python3 works), clone, and run `./install.sh`.
That's the whole reproduction - no manual launchctl, chmod, or settings editing.

## Reliable nightly sync

The nightly job runs at a fixed time via launchd. If your Mac sleeps before that time, launchd either misses the window or wakes into a state where Keychain access is degraded - causing the auth failure the job recovers from. On a Mac mini (always on AC), the fix is one command:

```bash
sudo pmset -a sleep 0
```

This disables system sleep while leaving display sleep alone. Equivalent to flipping "Prevent automatic sleeping when the display is off" in System Settings > Energy Saver. Set it once; it persists across reboots. Not added to `install.sh` because it requires sudo and is optional (only needed if the Mac would otherwise sleep before the sync fires).

## Notes / limits

- The fetcher captures **claude.ai chats**, not Cowork/Code sessions. Those are
  picked up best-effort by `sessions_export.py` from `~/.claude/projects/**/*.jsonl`.
- The claude.ai web API is unofficial and can change; the fetcher reports a clear
  auth error (exit 2) if the cookie is rejected. `refresh_session_key.py` then
  re-reads the live cookie from the Claude desktop app and retries automatically.
- `refresh_session_key.py` reads the macOS Keychain (service "Claude Safe Storage",
  account "Claude Key") and the Claude app's local SQLite cookie DB. It uses only
  stdlib + CommonCrypto via ctypes. It will break if Anthropic changes the Electron
  cookie encryption scheme.
- launchd jobs run while you're logged in. The sync runs even with no app window open.

## Changelog

### v0.1.1 (2026-06-20)
- **Rescheduled sync to 3:00 AM, restart to 4:00 AM.** The previous order (restart at 3 AM, sync at 4:18 AM) caused the session cookie to be invalidated by the app restart before the sync could use it. Running the sync first and restarting after eliminates the auth failure window. Install default updated accordingly.
- Diagnosed Cloudflare TLS fingerprinting as the reason `curl` always returns 403 on valid keys while `urllib` succeeds - not an auth bug.
- Added `~/.config/brain-kit` to the Claude Code sandbox `allowRead` list so the sync log is readable from within a Claude session.

### v0.1 (2026-06-18)
First tagged release. Core pipeline working end-to-end:
- `fetch_chats.py` pulls claude.ai conversations via session cookie
- `sessions_export.py` captures local Claude Code sessions from JSONL
- `brain-sync.sh` orchestrates fetch → capture → consolidate with auth auto-recovery
- `refresh_session_key.py` decrypts the session cookie from the Claude desktop app's Keychain/SQLite store; validates the key against the server before writing so a stale cookie fails fast instead of wasting a retry
- `consolidate-brain` skill ingests inbox files into Obsidian notes with timestamps on every entry
- Claude app watchdog + daily restart keep the cookie store live for headless nightly runs
- `install.sh` / `uninstall.sh` fully idempotent; launchd jobs registered as Aqua session agents
