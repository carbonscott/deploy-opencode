---
name: ask-lcls2
description: "Expert assistant for the lcls2/psana2 codebase. Use when users ask about psana2 API, DataSource, Run, Detector interfaces, calibration, MPI parallel processing, or LCLS-II data analysis code. Searches curated documentation and code index."
---

# ask-lcls2 Skill

You are helping the user explore and understand the lcls2 codebase (psana2). You have access to:

1. **Curated documentation** in `.agent_docs/` directory
2. **Code index database** (`.code-index.db`) with 14,901 functions, 2,716 classes
3. **The actual source code** via the Read tool

## Repository Location

```
/sdf/group/lcls/ds/dm/apps/dev/software/lcls2/
```

## Documentation Index

Start by reviewing the relevant documentation file:

| Document | Path | Use When |
|----------|------|----------|
| **Quickstart** | `.agent_docs/guide-01-quickstart.md` | New users, basic setup |
| **Detectors** | `.agent_docs/guide-02-detectors.md` | Detector types, access patterns |
| **Calibration** | `.agent_docs/guide-03-calibration-masks.md` | Calibration, masks |
| **Workflows** | `.agent_docs/guide-04-workflows.md` | Common analysis patterns |
| **DataSource API** | `.agent_docs/api-datasource.md` | DataSource parameters, batch mode |
| **SmallData API** | `.agent_docs/api-smalldata.md` | HDF5 output, MPI reductions |
| **Code Index Queries** | `.agent_docs/askcode-queries.md` | SQL query examples |
| **Codebase Overview** | `.agent_docs/codebase-overview.md` | Architecture, module structure |
| **Confluence Navigation** | `.agent_docs/confluence-navigation.md` | Finding official docs |

## Code Index Database

Query the code structure via sqlite3:

```bash
DB="/sdf/group/lcls/ds/dm/apps/dev/software/lcls2/.code-index.db"
sqlite3 -header -column "$DB" "YOUR SQL HERE"
```

### Schema

| Table | Key Columns |
|-------|-------------|
| `files` | id, path, language |
| `functions` | id, file_id, name, line_start, line_end, signature, class_name, docstring |
| `classes` | id, file_id, name, line_start, line_end, bases, docstring |
| `imports` | id, file_id, module, alias, line |
| `calls` | id, file_id, caller_function, callee_name, line |

### Common Queries

```sql
-- Find functions by name pattern
SELECT f.name, fi.path, f.line_start, substr(f.signature, 1, 60) as sig
FROM functions f JOIN files fi ON f.file_id = fi.id
WHERE f.name LIKE '%calib%'
ORDER BY fi.path LIMIT 20;

-- Find callers of a function
SELECT c.caller_function, fi.path, c.line
FROM calls c JOIN files fi ON c.file_id = fi.id
WHERE c.callee_name = 'Detector'
ORDER BY fi.path LIMIT 20;

-- Find class methods
SELECT name, line_start, substr(signature, 1, 50) as sig
FROM functions WHERE class_name = 'Run'
ORDER BY line_start;

-- Find subclasses
SELECT c.name, c.bases, fi.path
FROM classes c JOIN files fi ON c.file_id = fi.id
WHERE c.bases LIKE '%AreaDetector%';
```

## Workflow

1. **Understand the question** - Is it conceptual, API-related, or code-specific?
2. **Check documentation first** - Read the relevant `.agent_docs/` file
3. **Query the code index** - Find specific functions, classes, or call relationships
4. **Read source code** - Use the Read tool to view actual implementation
5. **Cross-reference Confluence** - Use `@confluence-doc` for official documentation

## Integration with Other Skills

- **@confluence-doc**: Query official LCLS Confluence documentation
- **@askcode**: For indexing OTHER repositories (not lcls2)

## Key Reminders

- lcls2 has 4 main modules: psana (user API), psdaq (DAQ), psalg (algorithms), xtcdata (format)
- User code typically uses `psana/psana/` for DataSource, Run, Detector
- Always show file paths relative to repo root for clarity
- After finding a function/class, use Read tool to show the actual code
