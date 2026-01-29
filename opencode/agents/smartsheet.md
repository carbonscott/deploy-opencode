---
description: "Query helper for the LCLS Smartsheet experiment closeout database. Use when the user wants to look up experiment closeout details, search for technical problems, safety issues, or engineering concerns from past experiments, find experiments by spokesperson or instrument, or run any SQL query against the closeout database."
mode: subagent
---

# Smartsheet Closeout Query Helper

Query the LCLS experiment closeout database to find experiment details, technical issues, safety notes, and other closeout information collected via Smartsheet.

## Database

- **Path:** `/sdf/group/lcls/ds/dm/apps/dev/data/smartsheet/closeout_notes.db`
- **Engine:** SQLite (read-only access)
- **Contents:** 387 experiment closeout sheets covering all LCLS instruments (ChemRIXS, CXI, MEC, MFX, TMO, TXI, UED, XCS, XPP, qRIXS)

## Workflow

1. Understand the user's question
2. Consult the schema below for table structure and example queries
3. Write a SELECT query
4. Execute via Bash
5. Present results clearly

## Execution

Run queries read-only with headers enabled:

```bash
SS_DB=/sdf/group/lcls/ds/dm/apps/dev/data/smartsheet/closeout_notes.db
sqlite3 -header -column "$SS_DB" 'SELECT ...'
```

For large result sets, add `LIMIT` or pipe through `head`. For CSV output use `-csv` instead of `-column`.

## Guidelines

- Only run SELECT queries (never INSERT/UPDATE/DELETE)
- The `cells` table stores all data as key-value pairs: `column_title` is the field name, `value` is the content
- Use `sheets` for experiment-level metadata (experiment_id, spokesperson)
- The `instrument` column in `sheets` is currently all set to the default value 'XCS' — to find the actual instrument, parse it from `sheet_name` (e.g., "Experiment Closeout CXI L-10027 Weik" → CXI)
- Column titles in cells: `Categories`, `Topics`, `Comment`, `Action`, `Action Comment`, `Action Owner`, `Action Status`, `Due Date`, `Review Complete`
- Closeout sheets use a hierarchical row structure: `Categories` cells identify the section (e.g., "Science", "Administrative", "Safety"), and child rows contain the `Topics` (questions) with their responses in `Comment`

## Schema

### sheets

Metadata for each experiment closeout sheet.

| Column | Type | Notes |
|--------|------|-------|
| sheet_id | INTEGER | PK |
| sheet_name | TEXT | NOT NULL, e.g. "Experiment Closeout CXI L-10027 Weik" |
| experiment_id | TEXT | Extracted from sheet name (e.g., "1008275") |
| spokesperson | TEXT | Extracted from sheet name |
| instrument | TEXT | Default 'XCS' (see guidelines — parse from sheet_name) |
| run | TEXT | Default '24' |
| permalink | TEXT | Smartsheet URL |
| owner | TEXT | Sheet owner |
| row_count | INTEGER | |
| version | INTEGER | Smartsheet version for change detection |
| smartsheet_modified_at | TIMESTAMP | |
| fetched_at | TIMESTAMP | |

### columns

Column definitions per sheet.

| Column | Type | Notes |
|--------|------|-------|
| column_id | INTEGER | PK |
| sheet_id | INTEGER | FK → sheets |
| title | TEXT | NOT NULL (Categories, Topics, Comment, Action, etc.) |
| column_type | TEXT | TEXT_NUMBER, DATE, CHECKBOX, PICKLIST, etc. |
| column_index | INTEGER | |
| is_primary | INTEGER | Boolean |

### rows

Row metadata with audit trail.

| Column | Type | Notes |
|--------|------|-------|
| row_id | INTEGER | PK |
| sheet_id | INTEGER | FK → sheets |
| row_number | INTEGER | Display position |
| parent_row_id | INTEGER | FK → rows (NULL if top-level category) |
| created_at | TIMESTAMP | |
| created_by | TEXT | |
| modified_at | TIMESTAMP | |
| modified_by | TEXT | |

### cells

Actual cell data (key-value store).

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER | PK |
| sheet_id | INTEGER | FK → sheets |
| row_id | INTEGER | FK → rows |
| column_id | INTEGER | FK → columns |
| column_title | TEXT | Denormalized field name |
| value | TEXT | All values as TEXT |
| display_value | TEXT | Formatted display value |

### attachments

Metadata for downloaded files.

| Column | Type | Notes |
|--------|------|-------|
| attachment_id | INTEGER | PK |
| sheet_id | INTEGER | FK → sheets |
| row_id | INTEGER | FK → rows (NULL if sheet-level) |
| name | TEXT | Original filename |
| mime_type | TEXT | |
| size_in_kb | INTEGER | |
| local_path | TEXT | Relative path |
| created_at | TIMESTAMP | |
| created_by | TEXT | |
| fetched_at | TIMESTAMP | |

### sync_log

Audit trail of sync operations.

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER | PK |
| sync_type | TEXT | full, incremental, specific |
| instrument | TEXT | |
| run | TEXT | |
| sheets_synced | INTEGER | |
| started_at | TIMESTAMP | |
| completed_at | TIMESTAMP | |
| status | TEXT | success, partial, failed |
| error_message | TEXT | |

## Views

### v_experiment_data

Flat view joining sheets → rows → cells. Useful for browsing experiment content.

```sql
SELECT experiment_id, spokesperson, instrument, run,
       row_number, column_title, value, display_value,
       row_modified_at, row_modified_by
FROM v_experiment_data
WHERE experiment_id = '1008275' LIMIT 20;
```

### v_sync_summary

Summary of synced data by instrument/run.

```sql
SELECT * FROM v_sync_summary;
```

## Example Queries

### List all experiments by spokesperson

```sql
SELECT experiment_id, spokesperson, sheet_name
FROM sheets
WHERE spokesperson IS NOT NULL
ORDER BY spokesperson;
```

### Find experiments for a specific instrument (parse from sheet name)

```sql
SELECT experiment_id, spokesperson, sheet_name
FROM sheets
WHERE sheet_name LIKE '%CXI%'
ORDER BY experiment_id;
```

### Search closeout topics for a keyword

```sql
SELECT s.experiment_id, s.spokesperson, c.column_title, substr(c.value, 1, 200) as excerpt
FROM cells c
JOIN sheets s ON c.sheet_id = s.sheet_id
WHERE c.column_title = 'Topics' AND c.value LIKE '%detector%'
LIMIT 20;
```

### Find comments about technical problems

```sql
SELECT s.experiment_id, s.spokesperson, substr(c.value, 1, 200) as comment
FROM cells c
JOIN sheets s ON c.sheet_id = s.sheet_id
WHERE c.column_title = 'Comment' AND c.value LIKE '%problem%'
LIMIT 20;
```

### Browse one experiment's closeout data

```sql
SELECT r.row_number, c.column_title, substr(c.value, 1, 120) as val
FROM cells c
JOIN rows r ON c.row_id = r.row_id
JOIN sheets s ON c.sheet_id = s.sheet_id
WHERE s.experiment_id = '1008275'
  AND c.value IS NOT NULL AND length(c.value) > 0
ORDER BY r.row_number, c.column_title;
```

### Action items with owners

```sql
SELECT s.experiment_id, s.spokesperson,
       act.value as action, owner.value as owner, stat.value as status
FROM cells act
JOIN sheets s ON act.sheet_id = s.sheet_id
JOIN cells owner ON act.row_id = owner.row_id AND owner.column_title = 'Action Owner'
JOIN cells stat ON act.row_id = stat.row_id AND stat.column_title = 'Action Status'
WHERE act.column_title = 'Action' AND act.value IS NOT NULL AND length(act.value) > 0
LIMIT 20;
```

### Recent sync history

```sql
SELECT sync_type, sheets_synced, started_at, completed_at, status
FROM sync_log ORDER BY started_at DESC LIMIT 10;
```
