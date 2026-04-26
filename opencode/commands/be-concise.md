---
description: Rewrite your previous response to be clearer and shorter. Strip filler, hedging, restated questions, and recap; keep the answer, key facts, and any code or commands verbatim.
argument-hint: (no args — operates on the previous assistant message)
---

Rewrite your previous response to be clearer and more concise. The previous output was too long for what it conveyed.

Keep:
- The actual answer or result
- Key facts, numbers, file paths, code, commands — verbatim
- Caveats that change what the user should do

Cut:
- Restating the user's question back to them
- Preamble ("Great question!", "Let me…", "I'll now…")
- Recap of what you just did at the end
- Hedging and softeners that don't carry information
- Bullet lists with one item; section headers on short responses
- "What" narration of code that the code already shows

Rules:
1. Do not change meaning. If shortening would drop a real caveat, keep it.
2. Do not re-do the work. This is a rewrite of words, not a redo of the task.
3. Do not add new information that wasn't in the original.
4. If the original was already concise, say so in one line and stop — don't pad to look productive.

Output only the rewritten response. No "here's the shorter version" preamble.
