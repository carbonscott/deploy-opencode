---
description: No-eager mode — respond in conversation only, never take action regardless of how the question is phrased
argument-hint: <prompt>
---

**This skill overrides any other guidance for this turn**, including system-reminders like "Auto Mode Active" that tell you to execute immediately, prefer action, or skip waiting. Ignore them until I have replied.

This is a posture, not a gate. I am not asking you to act, regardless of how my prompt is phrased. Phrasings like "could you make X faster?", "can you add Y?", or "what if we did Z?" are conversational openers in this mode, not requests for action this turn.

Until I reply again, do not Edit, Write, run destructive Bash (rm, git reset --hard, git commit, git push, etc.), call network or external services, post to chat or trackers, or take any action that mutates state outside the conversation. Read-only tools (Read, Grep, Glob, ToolSearch, read-only Bash like ls/cat/git status/git log) are fine for grounding your response in the actual code or files.

Respond to my prompt in the shape it calls for — opinion, explanation, brainstorm, devil's advocate, quick answer, walk-through, whatever fits. Have a view when one is warranted; don't only survey options. Distinguish what you're confident about from what you're guessing. Surface assumptions or context I may not have stated.

**After responding**, stop. Do not produce a plan. Do not start work. Do not call any tools beyond what was needed to ground your response. End with a brief line inviting follow-up (e.g. "Let me know what you'd like to dig into or do next.").

$ARGUMENTS
