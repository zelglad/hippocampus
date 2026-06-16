# brain-kit

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
| `bin/brain-sync.sh` | The nightly wrapper: fetch, capture, then consolidate. |
| `skills/consolidate-brain/SKILL.md` | The Claude skill that does the actual ingestion with judgment. |
| `templates/` | launchd job + security settings, with placeholders the installer fills in. |
| `install.sh` / `uninstall.sh` | Idempotent setup / teardown. |

The split is deliberate: **deterministic work (fetching, file moves) is plain
Python; work that needs judgment (what to keep, where it goes) is a Claude skill;
setup is a shell installer.** Don't collapse these into one thing.

## Install

```bash
git clone <this-repo> brain-kit
cd brain-kit
./install.sh
```

The installer asks for: your vault path, the `claude` binary path, a session name,
and the sync time. It then writes config to `~/.config/brain-kit/`, installs the
scripts and skill, applies the security settings to your vault, and schedules the
nightly launchd job. Re-running it is safe.

You'll be prompted once for your **claude.ai sessionKey** cookie
(DevTools > Application > Cookies > claude.ai > `sessionKey`, starts with
`sk-ant-sid01-`). It is stored at `~/.config/brain-kit/session.key` with `600`
permissions and is never committed. When it expires (every few weeks) the nightly
job sends a macOS notification; just paste a fresh one into that file.

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

## Sharing with others (GitLab)

This repo is safe to publish: it contains no paths, usernames, or secrets - only
placeholders the installer fills in per machine. To share with specific people:

1. Push to a **private** project on your GitLab.
2. Add them under **Project > Manage > Members** (or share with a group).

They clone, run `./install.sh`, and paste their own sessionKey and vault path.
Nothing of yours is baked in.

## Reproduce on a new Mac

Install prerequisites (`brew install python@3.13` if you want a pinned Python; the
scripts only use stdlib so any python3 works), clone, and run `./install.sh`.
That's the whole reproduction - no manual launchctl, chmod, or settings editing.

## Notes / limits

- The fetcher captures **claude.ai chats**, not Cowork/Code sessions. Those are
  picked up best-effort by `sessions_export.py` from `~/.claude/projects/**/*.jsonl`.
- The claude.ai web API is unofficial and can change; the fetcher reports a clear
  auth error (exit 2) if the cookie is rejected.
- launchd jobs run while you're logged in. The job runs even with no app open.
