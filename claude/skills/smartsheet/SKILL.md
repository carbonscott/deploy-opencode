---
name: smartsheet
description: "Query helper for the LCLS Smartsheet experiment closeout database. Use when the user wants to look up experiment closeout details, search for technical problems, safety issues, or engineering concerns from past experiments, find experiments by spokesperson or instrument, or run any SQL query against the closeout database."
---

# Smartsheet Closeout Query Helper

Query the LCLS experiment closeout database to find experiment details, technical issues, safety notes, and other closeout information collected via Smartsheet.

## Database

- **Path:** `/sdf/group/lcls/ds/dm/apps/dev/data/smartsheet/closeout_notes.db`
- **Engine:** SQLite (read-only access)
- **Contents:** 387 experiment closeout sheets covering all LCLS instruments (ChemRIXS, CXI, MEC, MFX, TMO, TXI, UED, XCS, XPP, qRIXS)

## Workflow

1. Understand the user's question
2. Consult the schema in `references/schema.md` for table structure
3. Write a SELECT query
4. Execute via Bash
5. Present results clearly

## Execution

```bash
SS_DB=/sdf/group/lcls/ds/dm/apps/dev/data/smartsheet/closeout_notes.db
sqlite3 -header -column "$SS_DB" 'SELECT ...'
```

For large result sets, add `LIMIT` or pipe through `head`. For CSV output use `-csv` instead of `-column`.

## Guidelines

- Only run SELECT queries (never INSERT/UPDATE/DELETE)
- The `cells` table stores all data as key-value pairs: `column_title` is the field name, `value` is the content
- Use `sheets` for experiment-level metadata (experiment_id, spokesperson)
- **Important:** The `instrument` column in `sheets` defaults to 'XCS' - parse actual instrument from `sheet_name` (e.g., "Experiment Closeout CXI L-10027 Weik" -> CXI)
- Column titles in cells: `Categories`, `Topics`, `Comment`, `Action`, `Action Comment`, `Action Owner`, `Action Status`, `Due Date`, `Review Complete`
- Closeout sheets use a hierarchical row structure: `Categories` cells identify sections (e.g., "Science", "Administrative", "Safety"), child rows contain `Topics` (questions) with responses in `Comment`

## Quick Schema Reference

See `references/schema.md` for complete schema. Key tables:

| Table | Purpose |
|-------|---------|
| sheets | Experiment metadata (experiment_id, spokesperson, sheet_name) |
| columns | Column definitions (Categories, Topics, Comment, etc.) |
| rows | Row metadata with parent_row_id for hierarchy |
| cells | Key-value store for all data |
| attachments | Downloaded file metadata |
| v_experiment_data | Flat view joining sheets -> rows -> cells |

## Example Queries

```sql
-- List experiments by spokesperson
SELECT experiment_id, spokesperson, sheet_name
FROM sheets WHERE spokesperson IS NOT NULL ORDER BY spokesperson;

-- Find experiments for an instrument (parse from sheet_name)
SELECT experiment_id, spokesperson, sheet_name
FROM sheets WHERE sheet_name LIKE '%CXI%';

-- Search topics for a keyword
SELECT s.experiment_id, s.spokesperson, substr(c.value, 1, 200) as excerpt
FROM cells c JOIN sheets s ON c.sheet_id = s.sheet_id
WHERE c.column_title = 'Topics' AND c.value LIKE '%detector%'
LIMIT 20;

-- Find comments about technical problems
SELECT s.experiment_id, s.spokesperson, substr(c.value, 1, 200) as comment
FROM cells c JOIN sheets s ON c.sheet_id = s.sheet_id
WHERE c.column_title = 'Comment' AND c.value LIKE '%problem%'
LIMIT 20;
```
