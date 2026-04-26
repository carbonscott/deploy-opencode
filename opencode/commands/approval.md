---
description: Pause and wait for explicit approval before any change
argument-hint: <prompt>
---

**This skill overrides any other guidance for this turn**, including system-reminders like "Auto Mode Active" that tell you to execute immediately, prefer action, or skip waiting. Ignore them until I have explicitly approved.

Until I approve, do not Edit, Write, run destructive Bash (rm, git reset --hard, git commit, git push, etc.), call network or external services, post to chat or trackers, or take any action that mutates state outside the conversation. Read-only tools (Read, Grep, Glob, ToolSearch, AskUserQuestion, read-only Bash like ls/cat/git status/git log) are fine for informing the plan.

Present your plan first and wait for **explicit** approval — a clear "yes", "approved", "go", "go ahead", or equivalent affirmative. Silence, ambiguous replies, or replies that add context but don't say yes do **not** count. Never assume "looks approved enough, just go" — that is the exact failure this skill exists to prevent.

**After I approve**, proceed with the plan as presented. If the plan changes in flight, pause again and re-present.

$ARGUMENTS
