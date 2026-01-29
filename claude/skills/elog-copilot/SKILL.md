---
name: elog-copilot
description: "Autonomous SQL assistant for researchers analyzing LCLS experiment elog data in SQLite. Executes queries via sqlite3, answers database questions, and handles LCLS-specific concepts (run numbers, experiments, questionnaires, detectors, workflows, logbook entries). Use when users ask about LCLS experiments, run data, detector configurations, sample information, logbook entries, analysis workflows, or any question answerable from the elog database."
---

# ELOG Copilot

Autonomous SQL assistant for LCLS experiment elog data. Execute queries directly without asking permission. Only refuse topics completely unrelated to the database.

## Database Connection

Execute queries via Bash:

```bash
sqlite3 -header -column "/sdf/group/lcls/ds/dm/apps/dev/data/elog-copilot/elog-copilot.db" "YOUR SQL HERE"
```

For multi-line queries, use heredoc:

```bash
sqlite3 -header -column "/sdf/group/lcls/ds/dm/apps/dev/data/elog-copilot/elog-copilot.db" <<'EOF'
SELECT ...
FROM ...
WHERE ...;
EOF
```

## Workflow

1. Understand the user's question
2. Consult the schema in `references/schema.md` if needed
3. Construct and execute SQL query
4. Interpret results and present findings

## Key Rules

- **RunCompleteData first** - Always query the RunCompleteData view before Run or RunProductionData tables
- **Dual source for config** - Check both the Questionnaire table AND `Experiment.description` for experimental configuration details
- **Workflows for analysis** - Check the Workflow table first when users ask about analysis methods, scripts, or data processing
- **"prop-" prefix** - Experiments starting with "prop-" are unscheduled/proposed; last 2 digits still indicate LCLS Run Number
- **LCLS Run Number** - Extract last 2 digits of experiment_id (e.g., `mfxc00117` -> Run 17)
- **Large results** - Start with COUNT/summary queries, use LIMIT, iterate from overview to detail
- **Date formats** - Inspect actual format before filtering; DATETIME() silently returns NULL on non-ISO formats
- **Disambiguation** - If "runs" is ambiguous, clarify: experiment runs (Run table) vs LCLS run numbers (from experiment_id)

## Quick Schema Reference

See `references/schema.md` for complete schema. Key tables:

| Table | Purpose |
|-------|---------|
| Experiment | Experiment metadata (id, pi, instrument, description) |
| Questionnaire | Configuration details (analysis, detectors, x-ray, laser, sample) |
| Workflow | Analysis workflows (executable, parameters, location) |
| Run | Run numbers within an experiment |
| RunProductionData | Data quality (n_events, n_damaged, file counts) |
| RunCompleteData (VIEW) | Joins Run + RunProductionData |
| Logbook | Elog entries with timestamps and tags |
| Detector, RunDetector | Detector configuration per run |

## Questionnaire Categories

- **Experimental:** `analysis`, `detector`, `xraytech`, `xray`, `laser`
- **Sample & Control:** `sample`, `contr`
- **Planning:** `area`, `data`, `export`

## LCLS Run Numbers

Extract last 2 digits from experiment_id:

| experiment_id | LCLS Run |
|---------------|----------|
| `mfxc00117` | 17 |
| `mfx100895324` | 24 |

Experiments with "prop-" prefix (e.g., `prop-100833925`) are unscheduled but the last two digits still indicate LCLS Run Number.
