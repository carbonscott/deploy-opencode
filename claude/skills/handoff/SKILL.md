---
description: Produce a self-contained hand-off document that lets a fresh Claude agent (or human with zero shared context) pick up the conversation — whether to execute a plan we've converged on or to keep the discussion going. Two-phase — audit the conversation into goal / decisions / ruled-out / assumptions / open threads, then write only what passes the intern test (would the next agent act differently knowing this?). Fights chronological narration, hidden shared-context dependencies, and false-resolution bloat. Use for "hand this off", "brief an intern on this", "self-contained doc for another agent", "pass this to a fresh context window".
argument-hint: [topic — optional; defaults to current conversation]
---

You are in handoff mode. The user has been in a conversation with you — research, design, building, or exploring — and now wants to hand the state of that conversation to someone else: another Claude agent with a fresh context window, or a human teammate. Call that reader the **intern**: they have zero shared context, zero access to this chat, only the doc you write. Your job is to produce a brief that lets them continue the work without re-asking questions already answered. The governing rule: **no line earns space unless the intern would act differently knowing it.**

The output of this skill is *always* the seven-section handoff doc defined below. If the user names a topic, deliverable, or output format ("a cheatsheet as a slide", "a cleanup PR", "the migration plan"), that names the **subject** of the handoff — it becomes the Goal — never the format. The intern produces the artifact; you produce the brief that lets them.

Two phases. Always audit before writing. The audit IS the plan — present the bucket coverage before drafting the doc, and wait for approval.

**Phase 1 — Audit.** Walk the conversation end-to-end. Sort material into five buckets. Items that don't fit any bucket are almost certainly chronology or meta — cut.

- **Goal / frame** — what we're actually trying to do, and why *this* framing rather than another. The intern's north star.
- **Decisions locked in (with why)** — so the intern doesn't re-litigate. Every decision gets its reason; a decision without its reason will be reopened the first time someone pushes back.
- **Ruled out (with why)** — paths considered and rejected, so the intern doesn't rediscover dead-ends. Reason is mandatory here too — "we tried X and it didn't work" is useless without *how* it didn't work.
- **Load-bearing assumptions** — things unstated in the conversation but that the work depends on. Environment, constraints, stakeholder preferences, unstated goals. These are the silent killers of hand-offs.
- **Live / open threads** — what's still being figured out, unresolved questions, in-flight hypotheses. For exploratory hand-offs this is the fat bucket; for execution hand-offs it's thin but critical (the blockers).

Per-item check: *would the intern act differently knowing this?* If no, cut. If yes but the same info is recoverable from the repo / git log / existing docs, replace the item with a pointer and drop the content.

**Phase 2 — Write the doc.** One file, self-contained, scannable. Use the bucket names as section headings so the structure is visible. The *ratio* of content across sections reflects where the conversation actually is — a converged design conversation has a fat Decisions section and thin Open threads; an exploratory discussion has the inverse. Same template, different weight. Do not force balance. Do not invent content to fill thin sections.

Rules:

1. **Intern test.** Reader has zero shared context. No "as we discussed", no "the usual approach", no undefined jargon, no pronouns without antecedents. If a term is project-specific, define it on first use or link to where it's defined.
2. **State over story.** Do not narrate chronology ("first we tried X, then Y, then settled on Z"). Report the current state. The journey appears only when a rejected path specifically prevents a future mistake — and then it goes in Ruled out, not as a story.
3. **Cite *why*, not just *what*.** Decisions and rejections without reasons are unstable — the intern will reopen them. If you don't know the reason, say so explicitly rather than omitting.
4. **Don't duplicate the repo.** Anything recoverable from the codebase, git log, or existing docs becomes a pointer, not content. "See `src/foo.py` for the adapter" beats restating what the adapter does.
5. **Preserve uncertainty honestly.** If something is unresolved, label it so. Don't paper over genuine disagreement or parked questions with a false decision just to make the doc look clean.
6. **No editorializing, no meta, no pleasantries.** Cut "we had a productive conversation about…", "this has been a great exploration of…", "the user and I converged on…". None of that changes the intern's behavior.
7. **Keep open threads live.** A discussion-style hand-off should read like the conversation can continue, not like it ended. Open questions stay phrased as questions, hypotheses as hypotheses. Don't accidentally resolve things in the writing.
8. **If the conversation is too thin, say so.** Some conversations haven't produced enough to hand off — early exploration, mostly vibes. Don't fabricate structure. Write a short honest note: "Not enough concrete state yet to hand off. What exists so far: …" and stop. **A user-supplied topic or format does not, by itself, qualify as "too thin" — treat it as the Goal and proceed.**
9. **No dump-and-pray.** Pasting chat excerpts is not a hand-off. Every included item must have been audited and earned its place.
10. **Pointers over prose.** Filenames, function names, doc URLs, ticket IDs — name the artifact the intern should read, don't summarize it.

Output shape, in order:

1. **Audit summary**: count of items per bucket. Quick scan of what the doc will contain and where the weight sits.
2. **Wait for approval on coverage.** If the user says "you missed X" or "that's not actually decided", correct before writing.
3. **Ask where to save.** Before drafting, ask the user for the output path (e.g. "Where should I save this? e.g. `~/handoffs/foo.md`"). Wait for the answer; do not assume a default.
4. **Hand-off doc** with sections in this order:
   - **Goal** — 1–3 sentences. What, and why *this* framing.
   - **Current state** — where we are right now, in one paragraph. Mostly-decided? Still exploring? Blocked on a question? This is the intern's orientation.
   - **Decisions (with why)** — bulleted, each with its reason.
   - **Ruled out (with why)** — bulleted, each with its reason.
   - **Load-bearing assumptions** — bulleted. Things the intern must not silently violate.
   - **Open threads** — bulleted. What's still live. Questions stay as questions.
   - **Pointers** — files, commits, tickets, docs the intern should read first, each with a one-line "why this one".
5. **Self-check pass**: re-read as the intern. Flag any remaining shared-context dependencies, undefined terms, or state-vs-story slips. Fix before presenting.

Tone: cost-honest, terse, no cheerleading. The intern is smart but cold — give them what they need and nothing more. Match the voice the user has been using in the conversation; don't suddenly switch to corporate.

Subject of this handoff: $ARGUMENTS

If `$ARGUMENTS` is empty, infer the subject from the current conversation — do not ask the user to restate it.
