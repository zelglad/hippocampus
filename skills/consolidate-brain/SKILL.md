---
name: consolidate-brain
description: Fold newly fetched claude.ai conversations (and any captured local sessions) into the Obsidian second-brain vault - updating the right notes and project files, then archiving the processed chats. Use when chats/_inbox has new files, or when asked to ingest/consolidate the brain.
---

# Consolidate Brain

You maintain an Obsidian "second brain" vault. The current working directory IS the vault root. Operate only within it (the session is scoped here and you should never read or write outside it).

## What to do

1. **Read the index first.** Open `CLAUDE.md` (vault root) and `notes/_index.md` to learn the file map, the owner's voice, and the routing conventions. Skim existing notes you are about to touch so you match their structure and tone.

2. **Process the inbox.** For every markdown file in `chats/_inbox/` (and, if present, new files in `sessions/`):
   - Extract only **durable** content: facts, decisions, project status changes, new preferences, positions the owner holds, and standing to-dos. Skip transient chatter, one-off tech-support questions, and trivia that carries no lasting signal.
   - Fold each durable item into the **most relevant existing note or project file** under `notes/` and `projects/`, following the conventions already in that file. Update frontmatter `updated:` dates. If a major status changes (e.g. an offer, a closed claim, a completed milestone), also correct the matching line in `CLAUDE.md`.
   - **Timestamp every entry.** Prefix each new fact, decision, or update with the date it came from, derived from the chat's `created_at` or `updated_at` frontmatter. Format: `MMM D YYYY -` (e.g. `Jun 18 2026 -`). When appending to an existing bullet or section, add the date inline at the start of the new content. When a later conversation updates or contradicts an earlier entry, add a dated update line beneath it rather than silently overwriting. This creates a visible timeline of how facts and decisions evolved.
   - Create a new note only when something genuinely does not fit any existing file.

3. **Archive what you processed.** Move each handled file from `chats/_inbox/` (or `sessions/`) into `chats/archive/` (create it if needed). Never delete - the archive is the lossless record.

## Fidelity rules (important)

- **Preserve, do not compress.** The owner explicitly does not want his memory or voice turned into a terse summary ("do not make an mp3 of it"). Capture nuance, specific numbers, reasoning, and his actual positions in his voice. He has storage and compute to spare. When in doubt, keep more.
- **Hyphens only.** No em dashes or en dashes anywhere.
- Do not invent facts. If a chat is ambiguous, capture what is actually stated and flag the uncertainty rather than resolving it.
- Curiosity threads (physics, animals, history, music, language) are part of the brain, not noise - record a faithful line in their topic note when a chat reflects a genuine recurring interest or a position he holds. Pure one-off generic facts can stay in the archive only.

## Reporting

End with a short report: what you ingested and into which files, what you corrected, and what you deliberately left in the archive as low-signal. If the inbox was empty, say so in one line.
