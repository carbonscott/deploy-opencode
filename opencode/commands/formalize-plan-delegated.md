---
name: formalize-plan-delegated
description: >-
  Formalize a plan that a subagent will execute after approval. Forces Claude
  into plan mode; the resulting plan must be self-contained because a cold
  subagent will run it. Triggers on: formalize plan for subagent, plan and
  delegate, plan for subagent execution.
---

# Formalize Plan (Delegated)

Enter plan mode immediately using the EnterPlanMode tool. Formalize the plan
before proceeding.

A subagent will execute this plan after approval. The subagent starts cold —
no conversation history, no shared context, just the prompt you pass it.
Write the plan as a self-contained briefing:

- Exact file paths and the specific changes in each (function names, what to
  add/remove/replace; line numbers where useful)
- Decisions already settled, with reasoning, so the subagent doesn't
  re-litigate them
- Success criteria — how the subagent knows it's done
- Anything explicitly out of scope

After approval, spawn a `general-purpose` subagent via the Agent tool with
the approved plan as the `prompt` (foreground, no worktree isolation by
default). Wait for completion and report results back.

$ARGUMENTS
