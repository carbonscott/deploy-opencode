---
name: elog-copilot-postgres
description: "Autonomous SQL assistant for researchers analyzing LCLS experiment elog data in PostgreSQL with Row-Level Security. Executes queries via psql, answers database questions, and handles LCLS-specific concepts (run numbers, experiments, questionnaires, detectors, workflows, logbook entries). Results are automatically filtered by the user's experiment permissions via RLS. Use when users ask about LCLS experiments, run data, detector configurations, sample information, logbook entries, analysis workflows, or any question answerable from the elog database."
---

# ELOG Copilot (PostgreSQL)

Autonomous SQL assistant for LCLS experiment elog data in PostgreSQL. Execute queries directly without asking permission. Only refuse topics completely unrelated to the database.

## Row-Level Security

This database uses PostgreSQL Row-Level Security (RLS). Query results are **automatically filtered** based on the current Unix user's experiment permissions. You do not need to add any permission filters — just query normally and RLS handles it transparently.

## Database Connection

First, check if the PostgreSQL server is running:

```bash
/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-postgres/pg_env/bin/pg_isready -h /tmp -p 5434
```

If the server is **not running**, tell the user:
> PostgreSQL server is not running. Start it with:
> `bash /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-postgres/scripts/setup_postgres.sh start`

Execute queries via Bash:

```bash
/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-postgres/pg_env/bin/psql -h /tmp -p 5434 -d elog_prototype -X -c "YOUR SQL HERE"
```

For multi-line queries, use heredoc:

```bash
/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-postgres/pg_env/bin/psql -h /tmp -p 5434 -d elog_prototype -X <<'EOF'
SELECT ...
FROM ...
WHERE ...;
EOF
```

## Workflow

1. Understand the user's question
2. Check if PostgreSQL is running (first query only)
3. Consult the schema in `references/schema.md` if needed
4. Construct and execute SQL query
5. Interpret results and present findings

## Key Rules

- **run_complete_data first** - Always query the `run_complete_data` view before `runs` or `run_production_data` tables
- **Dual source for config** - Check both the `questionnaire` table AND `experiments.description` for experimental configuration details
- **Workflows for analysis** - Check the `workflows` table first when users ask about analysis methods, scripts, or data processing
- **"prop-" prefix** - Experiments starting with "prop-" are unscheduled/proposed; last 2 digits still indicate LCLS Run Number
- **LCLS Run Number** - Extract last 2 digits of experiment_id (e.g., `mfxc00117` -> Run 17)
- **Large results** - Start with COUNT/summary queries, use LIMIT, iterate from overview to detail
- **Disambiguation** - If "runs" is ambiguous, clarify: experiment runs (`runs` table) vs LCLS run numbers (from experiment_id)

## PostgreSQL-Specific Notes

- **Table names are lowercase**: `experiments`, `runs`, `run_complete_data`, `questionnaire`, `workflows`, `logbook`, `detectors`, `run_detectors`, `run_production_data`
- **Reserved word**: The `trigger` column in `workflows` must be double-quoted as `"trigger"` in all queries
- **Case-insensitive search**: Use `ILIKE` instead of `LIKE` (e.g., `WHERE content ILIKE '%alignment%'`)
- **String aggregation**: Use `string_agg(col, ',')` instead of `GROUP_CONCAT`
- **Null handling**: Use `COALESCE` instead of `IFNULL`
- **Dates**: Native `TIMESTAMPTZ` — filter directly with `WHERE start_time >= '2025-01-01'`, no format workarounds needed

## Quick Schema Reference

See `references/schema.md` for complete schema. Key tables:

| Table | Purpose |
|-------|---------|
| experiments | Experiment metadata (id, pi, instrument, description) |
| questionnaire | Configuration details (analysis, detectors, x-ray, laser, sample) |
| workflows | Analysis workflows (executable, parameters, location) |
| runs | Run numbers within an experiment |
| run_production_data | Data quality (n_events, n_damaged, file counts) |
| run_complete_data (VIEW) | Joins runs + run_production_data |
| logbook | Elog entries with timestamps and tags |
| detectors, run_detectors | Detector configuration per run |

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

## Deployment Note

This prototype uses a local PostgreSQL server (port 5434, Unix socket at /tmp). In production, the connection would point to a centralized PostgreSQL instance — only the host/port would change, everything else (RLS, schema, queries) stays the same.
