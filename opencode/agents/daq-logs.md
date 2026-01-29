---
description: "Query helper for the LCLS DAQ log SQLite database. Use when the user wants to search DAQ errors, find problematic hosts/components, analyze error cascades by pulse_id, check ingestion status, or run any SQL query against the DAQ log database."
mode: subagent
---

# DAQ Log Query Helper

Query the LCLS DAQ log database to find errors, analyze cascades, and investigate component failures.

## Database

- **Path:** `/sdf/group/lcls/ds/dm/apps/dev/data/daq-logs/daq_logs.db`
- **Engine:** SQLite (read-only access)
- **Contents:** ~70k log files, all hutches (tmo, mfx, cxi, rix, xcs, xpp)

## Workflow

1. Understand the user's question
2. Consult the schema below for table structure and example queries
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

## Schema

### log_files

Metadata for each ingested log file.

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER | PK |
| filename | TEXT | NOT NULL, e.g. `04_09:23:16_drp-neh-ctl002:pvrtmon-fee.log` |
| hutch | TEXT | NOT NULL (tmo, mfx, cxi, rix, xcs, xpp) |
| start_timestamp_utc | DATETIME | NOT NULL |
| host | TEXT | NOT NULL |
| component | TEXT | NOT NULL |
| slurm_job_id | INTEGER | |
| platform | INTEGER | |
| cmdline | TEXT | |
| conda_prefix | TEXT | |
| testreldir | TEXT | |
| submoduledir | TEXT | |
| git_describe | TEXT | |
| file_path | TEXT | NOT NULL |
| file_size_bytes | INTEGER | |
| line_count | INTEGER | |
| has_errors | BOOLEAN | default FALSE |
| error_count | INTEGER | default 0 |
| created_at | DATETIME | default CURRENT_TIMESTAMP |

### log_errors

Individual errors extracted from log files.

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER | PK |
| log_file_id | INTEGER | FK -> log_files.id, NOT NULL |
| line_number | INTEGER | NOT NULL |
| timestamp_utc | DATETIME | |
| log_level | TEXT | E (Error) or C (Critical) |
| error_type | TEXT | daq, slurm, python, system |
| message | TEXT | NOT NULL |
| context_before | TEXT | 10 lines before error |
| context_after | TEXT | 10 lines after error |
| pulse_id | TEXT | for cascade analysis |
| epoch_sec | INTEGER | |
| epoch_nsec | INTEGER | |
| teb_id | INTEGER | |
| meb_id | INTEGER | |
| drp_id | INTEGER | |
| missing_source | TEXT | |
| missing_source_id | INTEGER | |
| failed_resource_type | TEXT | |
| failed_resource_id | INTEGER | |
| event_type | TEXT | |
| created_at | DATETIME | default CURRENT_TIMESTAMP |

### ingestion_runs

Tracks each ingestion execution.

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER | PK |
| run_timestamp | DATETIME | default CURRENT_TIMESTAMP |
| source_path | TEXT | NOT NULL |
| files_processed | INTEGER | |
| files_skipped | INTEGER | |
| errors_found | INTEGER | |
| duration_seconds | REAL | |
| status | TEXT | |

## Example Queries

### Errors by host

```sql
SELECT lf.host, COUNT(le.id) as errors
FROM log_files lf
JOIN log_errors le ON lf.id = le.log_file_id
GROUP BY lf.host ORDER BY errors DESC LIMIT 10;
```

### Errors by component

```sql
SELECT lf.component, COUNT(le.id) as errors
FROM log_files lf
JOIN log_errors le ON lf.id = le.log_file_id
GROUP BY lf.component ORDER BY errors DESC;
```

### Daily error summary

```sql
SELECT DATE(lf.start_timestamp_utc) as log_date, COUNT(le.id) as errors
FROM log_files lf
LEFT JOIN log_errors le ON lf.id = le.log_file_id
GROUP BY log_date ORDER BY log_date;
```

### Errors for a specific SLURM job

```sql
SELECT lf.filename, le.line_number, le.message
FROM log_files lf
JOIN log_errors le ON lf.id = le.log_file_id
WHERE lf.slurm_job_id = 853529;
```

### Error type distribution

```sql
SELECT error_type, log_level, COUNT(*) as count
FROM log_errors GROUP BY error_type, log_level ORDER BY count DESC;
```

### Components most often blamed for missing data

```sql
SELECT missing_source, COUNT(*) as times_blamed
FROM log_errors
WHERE missing_source IS NOT NULL
GROUP BY missing_source
ORDER BY times_blamed DESC LIMIT 10;
```

### Cascade events (single pulse_id affecting many components)

```sql
SELECT pulse_id,
       COUNT(DISTINCT lf.component) as affected_components,
       COUNT(*) as error_count
FROM log_errors le
JOIN log_files lf ON le.log_file_id = lf.id
WHERE le.pulse_id IS NOT NULL
GROUP BY le.pulse_id
HAVING affected_components > 3
ORDER BY affected_components DESC LIMIT 10;
```

### Trace a cascade by pulse_id

```sql
SELECT lf.component, lf.host, le.message, le.epoch_sec, le.epoch_nsec
FROM log_errors le
JOIN log_files lf ON le.log_file_id = lf.id
WHERE le.pulse_id = '<pulse_id_here>'
ORDER BY le.epoch_sec, le.epoch_nsec;
```

### TEB timeout events and downstream effects

```sql
SELECT le.teb_id, le.missing_source, COUNT(*) as occurrences
FROM log_errors le
WHERE le.teb_id IS NOT NULL AND le.missing_source IS NOT NULL
GROUP BY le.teb_id, le.missing_source
ORDER BY occurrences DESC LIMIT 20;
```

### Ingestion history

```sql
SELECT run_timestamp, source_path, files_processed, errors_found, status
FROM ingestion_runs ORDER BY run_timestamp DESC LIMIT 10;
```
