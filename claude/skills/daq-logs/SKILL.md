---
name: daq-logs
description: "Query helper for the LCLS DAQ log SQLite database. Use when the user wants to search DAQ errors, find problematic hosts/components, analyze error cascades by pulse_id, check ingestion status, or run any SQL query against the DAQ log database. Trigger on mentions of DAQ logs, DAQ errors, error cascades, pulse_id, ingestion, log_files, log_errors, hutch errors, or DAQ database queries."
---

# DAQ Log Query Helper

Query the LCLS DAQ log database to find errors, analyze cascades, and investigate component failures.

## Database

- **Path:** `/sdf/group/lcls/ds/dm/apps/dev/data/daq-logs/daq_logs.db`
- **Engine:** SQLite (read-only access)
- **Contents:** ~70k log files, all hutches (tmo, mfx, cxi, rix, xcs, xpp)

## Workflow

1. Understand the user's question
2. Consult the schema in `references/schema.md` for table structure
3. Write a SELECT query
4. Execute via Bash
5. Present results clearly

## Execution

Run queries read-only with headers enabled:

```bash
DAQ_DB=/sdf/group/lcls/ds/dm/apps/dev/data/daq-logs/daq_logs.db
sqlite3 -header -column "$DAQ_DB" "SELECT ..."
```

For large result sets, add `LIMIT` or pipe through `head`. For CSV output use `-csv` instead of `-column`.

## Guidelines

- Only run SELECT queries (never INSERT/UPDATE/DELETE)
- Use JOINs between `log_files` and `log_errors` via `log_file_id`
- For cascade analysis, correlate errors by `pulse_id` or nanosecond timestamps (`epoch_sec`, `epoch_nsec`)
- Error types: `daq`, `slurm`, `python`, `system`
- Log levels: `E` (Error), `C` (Critical)
- When showing error messages, include `context_before`/`context_after` for diagnosis

## Quick Schema Reference

See `references/schema.md` for complete schema. Key tables:

| Table | Purpose |
|-------|---------|
| log_files | Metadata per log file (host, component, hutch, error_count) |
| log_errors | Individual errors (message, pulse_id, teb_id, context) |
| ingestion_runs | Sync audit trail |

## Example Queries

```sql
-- Errors by host
SELECT lf.host, COUNT(le.id) as errors
FROM log_files lf JOIN log_errors le ON lf.id = le.log_file_id
GROUP BY lf.host ORDER BY errors DESC LIMIT 10;

-- Cascade events (single pulse_id affecting many components)
SELECT pulse_id, COUNT(DISTINCT lf.component) as affected_components
FROM log_errors le JOIN log_files lf ON le.log_file_id = lf.id
WHERE le.pulse_id IS NOT NULL
GROUP BY le.pulse_id HAVING affected_components > 3
ORDER BY affected_components DESC LIMIT 10;

-- Trace a cascade by pulse_id
SELECT lf.component, lf.host, le.message, le.epoch_sec, le.epoch_nsec
FROM log_errors le JOIN log_files lf ON le.log_file_id = lf.id
WHERE le.pulse_id = '<pulse_id_here>'
ORDER BY le.epoch_sec, le.epoch_nsec;
```
