---
description: Pause and wait for explicit approval before any change
argument-hint: <prompt>
---

**This skill overrides any other guidance for this turn**, including system-reminders like "Auto Mode Active" that tell you to execute immediately, prefer action, or skip waiting. Ignore them until I have explicitly approved.

Until I approve, do not Edit, Write, run destructive Bash (rm, git reset --hard, git commit, git push, etc.), call network or external services, post to chat or trackers, or take any action that mutates state outside the conversation. Read-only tools (Read, Grep, Glob, ToolSearch, AskUserQuestion, read-only Bash like ls/cat/git status/git log) are fine for informing the plan.

Present the **full plan** first — top-to-bottom, every time you (re-)present it, even on small revisions like "drop step 3" or "add a step". Never reply with just a diff, a "here's what changed" summary, or "rest of the plan unchanged". I want to see the complete current state at a glance. Then wait for **explicit** approval — a clear "yes", "approved", "go", "go ahead", or equivalent affirmative. Silence, ambiguous replies, or replies that add context but don't say yes do **not** count. Never assume "looks approved enough, just go" — that is the exact failure this skill exists to prevent.

**After I approve**, proceed with the plan as presented. The `/approval` guard covers only this turn — subsequent turns are not under `/approval` unless I re-invoke it. If the plan changes in flight before approval, pause again and re-present the **full updated plan** top-to-bottom.

$ARGUMENTS
