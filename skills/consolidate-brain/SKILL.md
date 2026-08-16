---
name: consolidate-brain
description: Fold newly fetched claude.ai conversations (and any captured local sessions) into the Obsidian second-brain vault - preserving the owner's voice, questions, and reasoning threads, not just extracted facts - then archiving the processed chats. Use when chats/_inbox has new files, or when asked to ingest/consolidate the brain.
---

# Consolidate Brain

You maintain an Obsidian "second brain" vault. The current working directory IS the vault root. Operate only within it (the session is scoped here and you should never read or write outside it).

## The goal - read this before the mechanics

This vault is not a fact database. It is a preserved mind. The test for every chat is not "what facts does this contain" but "reading this back in two years, would the owner recognize himself - his questions, his tangents, his voice?" A bare fact stripped of the question that produced it is the mp3 of a live performance. Store the performance.

Three layers to capture, in priority order:

1. **How he thinks.** The questions he actually asked (verbatim when they carry voice), the tangent jumps within a single chat (a hop from zoo hippos to siege famine to paleolithic eating is a reasoning chain, not noise), the positions he forms mid-conversation, the humor he processes heavy topics through.
2. **What he decided or believes.** Decisions, positions, preferences, standing to-dos, project status changes.
3. **What he learned.** The facts themselves, with full specifics - numbers, names, mechanisms, sources.

Most consolidation failures are layer 3 crowding out layers 1 and 2. If your output for a chat reads like an encyclopedia entry with no trace of the person who asked, you compressed too hard.

## What to do

1. **Read the index first.** Open `CLAUDE.md` (vault root) and `notes/_index.md` to learn the file map, the owner's voice, and the routing conventions. Skim existing notes you are about to touch so you match their structure and tone.

2. **Process the inbox.** For every markdown file in `chats/_inbox/` (and, if present, new files in `sessions/`):
   - Route content to the **most relevant existing note or project file** under `notes/` and `projects/`, following the conventions already in that file. Update frontmatter `updated:` dates. If a major status changes (e.g. an offer, a closed claim, a completed milestone), also correct the matching line in `CLAUDE.md`.
   - **Capture the thread, not just the extract.** When a chat shows a curiosity chain, record the chain itself: what he asked, in what order, and where it landed. Quote his actual phrasing when it carries personality - his words, never paraphrased into neutral assistant-prose.
   - **His questions are content.** What he asked reveals more than what he was told. A distinctive question gets recorded as his, attributed and dated, even when the answer was mundane.
   - Facts still get captured with full specifics. Layer 1 does not replace layer 3 - it wraps it.
   - **Timestamp every entry.** Prefix each new fact, decision, or thread with the date it came from, derived from the chat's `created_at` or `updated_at` frontmatter. Format: `MMM D YYYY -` (e.g. `Jun 18 2026 -`). When a later conversation updates or contradicts an earlier entry, add a dated update line beneath it rather than silently overwriting. This creates a visible timeline of how facts and positions evolved.

3. **Tag tangential entities as you fold content in.** A note's own core subject never needs tagging (don't tag "hippo" in the animals note) - this is only for things that would otherwise get lost because they're a tangent inside a note about something else, the same failure mode that made a whole Ghost in the Shell thread unfindable by keyword search for months. Three tag types, used together:
   - **Category tag** - a self-evident, browsable label: `#film`, `#anime`, `#book`, `#game`, `#band`, `#tv-show`, `#song`, `#historical-figure`, `#notable-animal`, `#mythology`, or whatever genuinely fits (don't force one of these if none apply). Only for titled works or named individuals/entities, never generic topics.
   - **Entity tag** - the specific name, lowercase-hyphenated (`#ghost-in-the-shell`, `#marcus-aurelius`), always paired with its category tag at the same mention. Before inventing one, grep the vault for the entity - if it's already tagged elsewhere, reuse the exact same tag so mentions across notes link up.
   - **Significance tag** - `#favorite`, `#bucket-list`, `#recurring-theme`, `#open-question` - stacks on top of the other two only when something actually crosses that threshold (an explicit "my favorite X" statement, a real standing plan, a topic that's now come up in a third note). Not for every mention.
   Place tags inline in the body at the point of actual relevance, not stacked onto the heading where they compete with the note's real topic.

4. **Create a new note when nothing fits.** Do not force an item into a note it only loosely belongs to - a wrong home is worse than a new file, because it makes the item unfindable later. Create `notes/<lowercase-hyphenated>.md` when **either** is true:
   - The item is a **new recurring subject**: it has come up in at least two separate conversations, or it is clearly a standing thread (a new job, a new legal matter, a new health track, a new build project), and no existing note covers it.
   - The item is substantial and its only plausible home would need a caveat to accept it ("filed here even though it isn't really about X").

   Do NOT create a note for a one-off fact, a single lookup, or a passing tangent - those either go in the closest topic note or stay in the archive. Match the existing structure: frontmatter (`title`, `type`, `tags`, `updated`), a `## Summary`, the content, and a `## Related` line. Then add it to `notes/_index.md` under the right heading, and link it from the most closely related existing note so it is not an orphan.

5. **Split a note when it has grown two distinct halves.** Check any note you touched that is over ~200 lines. Split it only when the content divides on a real seam, not just on size - the test is whether the two halves would be *looked up on different occasions*. Real seams look like: timeless reference/doctrine vs personal history; how-it-works vs how-I-built-it; a closed chapter vs live work. Not a seam: one subject that is simply long, or one narrative arc with many entries.

   When splitting: move the content **verbatim** (never rewrite or compress it), leave a short pointer plus a `[[wikilink]]` where it used to be, cross-link both files in their `## Related` lines, and add the new file to `notes/_index.md`. Say in the new note's Summary what was split from what and why.

6. **Build the lateral network, not just spokes off the index.** The value of this vault is note-to-note connection: `_index.md` is a table of contents, not the wiring. Links should run **directly between notes**, so a thread can be followed from wherever the owner happens to land. Three jobs here, in order:

   - **Link new content as you fold it in.** If an item touches a person, project, or concept covered in another note, add a `[[wikilink]]` inline at the point where it actually connects, not just in the `## Related` footer - the footer says two notes are related, an inline link says *how*. Only where the connection is genuine and would help future recall, never as a quota.
   - **Make topic-level relationships reciprocal.** If note A's `## Related` line names B, then B's should usually name A - otherwise the connection is only discoverable from one side. Check both ends. **Exception:** a passing inline tangent (a hippo aside inside an aviation chat) is legitimately one-way - do not force a return link for a mention that is not really about that subject. Reciprocate topic relationships; leave tangents directional.
   - **Notice unlinked pairs among notes you touched.** When two notes cover the same person, event, mechanism, or decision and neither links the other, connect them. This is the connection that would otherwise never form, because nothing in the new batch prompted it.

   Skip the whole step if nothing in the batch warrants it. Do not rewire the vault on a quiet night.

7. **Archive what you processed.** Move each handled file from `chats/_inbox/` (or `sessions/`) into `chats/archive/` (create it if needed). Never delete - the archive is the lossless record.

## Calibration example - a past mistake, do not repeat it

A chat titled "London Zoo hippo exhibits" opened with a zoo fact, then jumped: can people eat leather belts during a siege - what else gets eaten in famines - how long a human survives on water alone - how often humans ate 100k years ago. The old consolidation kept a 3-line zoo fact and dropped everything else as noise.

That was wrong. The famine chain was a genuine curiosity thread (history, human limits, mechanism - all recurring interests) and the jump itself is his signature. Correct handling: zoo fact to the animals note, and the famine/starvation chain - his questions and the conclusions - as a dated thread in the relevant curiosity note. When in doubt whether a tangent is a thread or noise: he topic-hops by nature, the hops are the fingerprint, keep the thread.

## Fidelity rules (important)

- **Preserve, do not compress.** The owner explicitly does not want his memory or voice turned into a terse summary ("do not make an mp3 of it"). Capture nuance, specific numbers, reasoning, and his actual positions in his voice. He has storage and compute to spare. When in doubt, keep more.
- **Voice-to-text artifacts:** he dictates a lot. Interpret intent and capture the meaning in his register - do not transcribe garble, and do not flatten his phrasing into tidy prose. "belive in me, I'll find Jessica" survives as "believe in me, I'll find Jessica," not as "he expressed optimism about visiting."
- **Hyphens only.** No em dashes or en dashes anywhere.
- Do not invent facts. If a chat is ambiguous, capture what is actually stated and flag the uncertainty rather than resolving it.
- Curiosity threads (physics, animals, history, music, language) are part of the brain, not noise. What may stay archive-only: pure logistics with no decision and no thread - one-off product searches, generic how-to lookups, transient tech support. Even then, if it touches an active project or a recurring interest, a one-line dated pointer in the topic note is cheap - add it.

## Reporting

End with a short report: what you ingested and into which files, which threads and voice you preserved, what you corrected, and what you deliberately left archive-only. If the inbox was empty, say so in one line.
