# Build Tools, Not Agents

*A tooling-first approach to AI agents for experimental science*

---

Everyone wants an AI agent.  The instinct is to fine-tune a model on your
domain data, or build a custom agent framework that defines exactly what
the agent can and cannot do.  Both are expensive, both lock you in, and
both miss where the real leverage is.

This document argues that an AI agent is three layers -- and you should
only invest in one of them.


## The Three Layers

```
┌─────────────────────────────────────────────────────────┐
│  (1) Model                                              │
│                                                         │
│  Claude, GPT, Llama, Gemini, ...                        │
│  Keep it general.  Don't fine-tune.                     │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  (2) Harness                                            │
│                                                         │
│  Claude Code, OpenCode, LangGraph, CrewAI, ...          │
│  Keep it swappable.  Don't over-customize.              │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  (3) Tooling                      <── invest here       │
│                                                         │
│  CLI tools, databases, cron pipelines, search indexes,  │
│  shell wrappers, documentation (including SKILL files   │
│  that teach the AI how to use the tools)                │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**The model** is the foundation.  You don't build it -- you rent it.
Fine-tuning couples you to a specific model version; when the next
generation arrives, your fine-tuning is gone and you pay the evaluation
cost all over again.  A general model, given good tools, performs well
enough.

**The harness** is the orchestration layer -- the thing that connects the
model to your tools, manages conversation, and controls permissions.
Today it might be Claude Code; tomorrow it might be something better.
Don't embed your domain logic here.  If the harness dies, your investment
should survive.

**The tooling** is where all the value lives.  CLI tools that query
databases.  Cron jobs that keep data fresh.  Search indexes that make
documentation discoverable.  Shell wrappers that isolate environments.
These are things you would build anyway -- they serve human users just as
well as AI agents.  The AI is a multiplier on tooling that already has
value.

The key insight: **better tooling enables both human agents and AI
agents.**  A CLI tool that queries your experiment database is useful to a
scientist typing commands in a terminal.  It's also useful to an AI agent
that translates natural language into those same commands.  The investment
pays off either way.


## SKILL Files Are Man Pages, Not Fine-Tuning

The obvious objection: "Your SKILL files contain domain-specific schemas,
query strategies, fallback logic, and naming conventions.  That's model
customization, not tooling."

It's not.  Here's the litmus test: **does it travel with the tool or with
the model?**

```
Fine-tuning                          SKILL file (man page)
─────────────                        ─────────────────────
Coupled to model version             Coupled to the tool
Dies when you switch models           Works with any model
Encoded in weights (opaque)          Encoded in text (readable)
Requires evaluation pipeline         Requires a text editor
Amortizes token cost                 Costs tokens at runtime
Cannot be version-controlled         Lives in git
Cannot be read by humans             Readable by anyone
```

A SKILL file is the AI equivalent of a man page.  It teaches the user --
human or AI -- how to use the tool.  It describes the interface, the
expected inputs, the known gotchas, and the common workflows.  Nobody
would call `man grep` "shell customization."  It's part of grep.

The token cost at runtime is real, but manageable.  A single skill
invocation loads one SKILL file, not all of them.  And unlike fine-tuning,
you never lose your investment when the model upgrades.


## Examples from Production

These examples are from a shared deployment at SLAC National Accelerator
Laboratory, serving LCLS (Linac Coherent Light Source) scientists and
engineers.  Each illustrates a different pattern of tooling-first design.


### Example 1: docs-index -- one tool, many skills

`docs-index` is a 360-line Python script that indexes documentation
collections into SQLite FTS5 databases and searches them with BM25
ranking.

```
$ docs-index index /path/to/docs --incremental
Indexed 847 files (23 new, 12 updated, 3 removed)

$ docs-index search /path/to/docs "batch job submission"
Score   File
─────   ────────────────────────────────
-8.23   docs/batch-compute.md
-7.41   docs/slurm-basics.md
-6.89   docs/gpu-jobs.md
```

This single tool powers multiple AI skills:

```
docs-index
    │
    ├── ask-s3df skill      (S3DF facility docs, daily cron sync)
    ├── ask-olcf skill      (OLCF facility docs, weekly cron sync)
    └── docs-search skill   (any doc collection, on-demand)
```

Each skill's SKILL file teaches the AI when to use `docs-index search`
versus `grep` versus reading files directly:

> Use `docs-index search` for **discovery**, then `Read` the top results.
> Use `Grep` when you need **precision** on a known pattern.

A human can run the same commands.  The AI adds convenience (natural
language queries) and judgment (choosing the right search strategy).  But
the tool works without the AI.

**Pattern: Build a general-purpose tool.  Write SKILL files to teach the
AI how to use it in different contexts.  The tool compounds in value as
you add more skills.**


### Example 2: elog-copilot -- cron pipeline meets AI

LCLS experiment metadata -- runs, detectors, sample configurations,
logbook entries -- lives behind a Kerberos-authenticated web API.
Scientists need to query it, but the API is not designed for ad-hoc
analysis.

The tooling solution:

```
Confluence/eLog API                     AI skill
       │                                    │
  ┌────▼────┐    every 6 hours    ┌─────────▼─────────┐
  │ elogfetch├───────────────────►│  SQLite database   │
  │ (cron)   │                    │  (~1.3 GB)         │
  └──────────┘                    │                    │
                                  │  9 tables:         │
                                  │  Experiment        │
                                  │  Run               │
                                  │  Detector          │
                                  │  Logbook           │
                                  │  Questionnaire     │
                                  │  ...               │
                                  └─────────┬──────────┘
                                            │
                                       sqlite3 CLI
                                            │
                                     ┌──────▼──────┐
                                     │ Human    or │
                                     │ AI agent    │
                                     └─────────────┘
```

The SKILL file teaches the AI the schema, domain conventions (LCLS run
numbers, experiment naming, questionnaire categories), and safety rules
(never SELECT full logbook content with inline base64 images -- use
`LENGTH()` and `SUBSTR()` to inspect first).

A human can query the same database directly:

```
$ sqlite3 /path/to/elog-copilot.db \
    "SELECT experiment_id, instrument, pi FROM Experiment
     WHERE instrument = 'mfx' ORDER BY start_time DESC LIMIT 5"
```

The AI adds the ability to ask "What detectors were used in recent MFX
experiments with protein crystallography samples?" and get back a
well-formed SQL query, executed and interpreted.  But the database, the
cron job, and the CLI tool exist independently of the AI.

**Pattern: Build a data pipeline (cron + database) that makes information
queryable.  The AI becomes a natural language interface to data that humans
can also query directly.**


### Example 3: ask-slurm-s3df -- wrapping existing system tools

S3DF runs Slurm 24.11.3 across 200+ nodes with 7 partition types.
Scientists struggle with job submission, pending reasons, GPU allocation,
and fairshare.  The commands exist (`sinfo`, `squeue`, `sacctmgr`) -- but
the output requires interpretation.

The tooling here is Slurm itself.  The SKILL file teaches the AI:

- Which commands always work vs. which need `slurmdbd` (and may fail):

  ```
  Always works          Needs slurmdbd (may fail)
  ────────────          ─────────────────────────
  sinfo                 sacctmgr
  squeue                sacct
  scontrol show         sshare
  sprio                 sreport
  ```

- What the output means (e.g., `AssocGrpNodeLimit` means the user's
  account has hit its allocation cap, not that the cluster is full)

- Partition specifications (7 partitions, their CPU/GPU models, memory,
  GRES names)

- Priority formula: `Priority = (QOS * 100K) + (FairShare * 10K) +
  (JobSize * 1K) + (Age * 100)`

A human can run `sinfo -p ampere -o "%N %G %T"` to check GPU
availability.  The AI adds interpretation: it explains *why* your job is
pending, suggests the right partition for your workload, and falls back
gracefully when `slurmdbd` is temporarily down.

**Pattern: You don't always need to build new tools.  Sometimes the tools
already exist -- you just need to write a man page that teaches the AI
how to use them and interpret the output.**


### Example 4: experimental-hutch-python -- the safety boundary

This is the most ambitious skill -- and the most instructive about where
safety belongs.

LCLS beamlines are controlled through `hutch-python`, an IPython-based
session running on DAQ nodes.  The skill lets an AI agent assist with
beamline operations through a bridge:

```
┌─────────┐    SSH tunnel (2 hops)    ┌───────────┐
│ AI agent│◄─────────────────────────►│  IPython  │
│ on SDF  │  JSON over netcat:9999    │  on DAQ   │
│         │                           │  node     │
│         │  {"code": "motor.mv(5)"}  │           │
│         │  ──────────────────────►  │  executes │
│         │                           │  on real  │
│         │  {"status": "ok",         │  beamline │
│         │   "result": "5.0"}        │  hardware │
│         │  ◄──────────────────────  │           │
└─────────┘                           └───────────┘
```

The safety architecture has two layers:

**Tooling-level safety (strong):**
- The bridge requires a two-hop SSH tunnel (SDF -> psdev -> hutch-daq) --
  you can't accidentally connect without deliberate infrastructure setup
- The bridge is a separate process that must be manually launched in the
  IPython session
- Network isolation: the AI runs on SDF, not on the DAQ node

**SKILL-file-level safety (weaker, model-dependent):**
- Read-only commands (`.position`, `.read()`, `wm_*()`) execute directly
- Write commands (`.mv()`, `RE(scan)`, `daq.begin()`) require explicit
  user confirmation before execution:

  > **I'd like to execute the following command:**
  > ```python
  > motor_x.mv(10.5)
  > ```
  > This will move motor_x from its current position to 10.5.
  >
  > **Shall I proceed?**

This skill honestly illustrates the framework's own principle: **safety
should be in the tooling, not the model.**  The SSH tunnel requirement
(tooling-level) is robust -- it's a physical infrastructure gate.  The
confirmation protocol (SKILL-file-level) depends on the model following
instructions, which is weaker.  The right next step is to build the
confirmation into the bridge itself -- a cryptographic token, a hardware
interlock, or a default-deny mode that requires explicit unlock.

**Pattern: When the stakes are high, don't rely on the AI following
instructions.  Build safety into the tooling infrastructure.  Use the
AI's judgment for convenience, not for safety.**


## Criticism and Defense

Any framework that claims "don't do X" should withstand scrutiny.  Here
are the strongest challenges to this approach, presented honestly.


### "You have no mechanism for multi-tool orchestration"

**The attack:** A question like "Why did experiment LY2523 have anomalous
detector readings, and is this related to the DAQ configuration changes
documented in Confluence last month?" requires querying the elog database,
the DAQ logs, and the Confluence docs.  Your framework has no workflow
graph, no shared state, no way to pipe one skill's output into another.
This is exactly what LangGraph solves.

**The defense:** The model handles this today.  In a single conversation,
the AI queries the elog database, then the DAQ logs, then searches
Confluence -- using the same tools it would use for single-skill queries.
The model's in-context reasoning is the orchestrator.  This works because
our tasks are primarily information retrieval with synthesis, not
multi-hour pipelines requiring checkpointing and rollback.

We concede: if you need *guaranteed* multi-step workflows with error
recovery and audit trails, a workflow engine is more reliable than hoping
the model self-organizes correctly.  But for the query-and-synthesize
pattern that dominates scientific computing, the general model handles
orchestration well enough.


### "Your beamline control safety is in the SKILL file, not in tooling"

**The attack:** The confirmation protocol for beamline commands lives in
the SKILL file, enforced by the model's compliance with instructions.  A
sufficiently creative prompt could bypass it.  By your own framework's
logic, this should be tooling-level safety.

**The defense:** This is correct.  The SSH tunnel requirement is genuine
tooling-level safety.  The confirmation protocol is not.  The skill is
labeled `[EXPERIMENTAL]` for exactly this reason.  The right fix is to
build confirmation into the bridge itself -- require a cryptographic
token, add a hardware interlock, or make the bridge read-only by default.
This critique strengthens the framework: the fix is more tooling, not more
model safety or more harness logic.


### "Context window creates a ceiling at scale"

**The attack:** At 15 skills, you can load 1-2 SKILL files per query.
At 100+ skills, the harness needs a routing layer to decide which SKILL
files to load.  That router is a harness-level component, contradicting
"keep the harness thin."

**The defense:** The routing already exists: the one-line skill
descriptions in the harness configuration serve as a lightweight index.
As skill count grows, this can be extended with a search index over skill
descriptions -- which is just another tool (and one we already have:
`docs-index` could index SKILL files the same way it indexes
documentation).  The architecture accommodates scale within its own
principles; it just needs one more tool.


### "You have no feedback loop"

**The attack:** There's no instrumentation for skill quality.  No logging
of which skills are invoked, no way to detect incorrect outputs, no A/B
testing for SKILL file modifications.  Without feedback, quality depends
on the maintainer's intuition.

**The defense:** This is a legitimate gap.  The fix is consistent with the
framework: build a logging tool.  A SQLite database recording skill
invocations, queries issued, and outcomes.  That's tooling, not model
customization or framework engineering.  The framework doesn't prevent
this; it just hasn't been built yet.


## The Practical Takeaway

If you want an AI agent for X, don't start with the agent.  Start with
the tool.

```
Step 1: Build a CLI tool that does X
        ┌──────────────────────────────┐
        │  $ my-tool query "..."       │
        │  $ my-tool search "..."      │
        │  $ my-tool status            │
        └──────────────────────────────┘
        A human can use this right now.

Step 2: Write a man page (SKILL file)
        ┌──────────────────────────────┐
        │  What the tool does          │
        │  What commands are available │
        │  What the schema looks like  │
        │  What the gotchas are        │
        │  What the safety rules are   │
        └──────────────────────────────┘
        A human would read this too.

Step 3: Hand both to an AI harness
        ┌──────────────────────────────┐
        │  The AI reads the man page,  │
        │  invokes the tool, and       │
        │  interprets the output.      │
        └──────────────────────────────┘
        Now you have an agent.
```

You didn't fine-tune a model.  You didn't build a framework.  You built a
tool that works for humans and wrote documentation that works for both
humans and AI.  If the model improves, your agent gets better for free.
If the harness changes, you move the man page.  Your investment is in the
tool -- and the tool was worth building anyway.

---

*This document reflects experience from the LCLS OpenCode deployment at
SLAC National Accelerator Laboratory, where ~15 AI skills serve
scientists and engineers across experiment operations, data analysis, and
facility computing.  The deployment runs on the S3DF HPC cluster using
general-purpose language models with no fine-tuning.  The deployment
serves experimental science workflows, not large-scale simulation.*
