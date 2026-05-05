---
description: No operation — absorb the provided context or read the referenced material, then stop. Use when the user wants the agent to take in information without acting on it. Triggers on "/no-op", "just read this", "just absorb this", "no action", "don't do anything yet", or any prompt where the user is loading context for a future request.
argument-hint: (optional — context, file path, or material to absorb)
---

The user wants you to take in context, not act on it. Your helpfulness instinct will push you to summarize, suggest next steps, fix things you noticed, or ask clarifying questions. Resist all of it.

Do:
- If a file path or reference was provided, read it once.
- Reply with a single short line confirming you've absorbed the context (e.g. "Read." or "Got it.").
- Stop. Wait for the next instruction.

Do not:
- Summarize what you read.
- List what you noticed, what stood out, or what seems important.
- Propose next steps, offer help, or ask "want me to…" questions.
- Fix typos, suggest improvements, or flag issues — even small ones.
- Call any tool other than the single Read needed to load a referenced file.
- Schedule follow-ups or offer to /schedule anything.

If the user's prompt mixes context-loading with an actual request, the actual request wins — treat /no-op as overridden and do the work. This skill is only for the pure "just take this in" case.
