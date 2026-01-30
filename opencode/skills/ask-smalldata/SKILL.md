---
name: ask-smalldata
description: "Expert assistant for smalldata_tools codebase. Use when users ask about DetObjectFunc, ROI, azimuthal binning, droplet/photon detection, smd_producer, cube production, SmallDataAna, or LCLS smalldata HDF5 processing code."
---

# ask-smalldata Skill

You are helping the user explore and understand the smalldata_tools codebase. You have access to:

1. **Curated documentation** in `.agent_docs/` directory
2. **Code index database** (`.code-index.db`) with 940 functions, 144 classes
3. **The actual source code** via the Read tool

## Repository Location

```
/sdf/group/lcls/ds/dm/apps/dev/software/smalldata_tools/
```

## Documentation Index

Start by reviewing the relevant documentation file:

| Document | Path | Use When |
|----------|------|----------|
| **Quickstart** | `.agent_docs/guide-01-quickstart.md` | Getting started, basic workflow |
| **Producer Config** | `.agent_docs/guide-02-producer-config.md` | smd_producer setup, YAML config |
| **SmallDataAna** | `.agent_docs/guide-03-smalldataana.md` | Interactive HDF5 analysis |
| **Workflows** | `.agent_docs/guide-04-workflows.md` | Common analysis patterns |
| **Ana Funcs Reference** | `.agent_docs/ana-funcs-reference.md` | All DetObjectFunc subclasses |
| **Code Index Queries** | `.agent_docs/askcode-queries.md` | SQL query examples |
| **Codebase Overview** | `.agent_docs/codebase-overview.md` | Architecture, class hierarchy |
| **Confluence Navigation** | `.agent_docs/confluence-smalldata-tools.md` | Finding official docs |

## Code Index Database

Query the code structure via sqlite3:

```bash
DB="/sdf/group/lcls/ds/dm/apps/dev/software/smalldata_tools/.code-index.db"
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
-- Find all DetObjectFunc subclasses
SELECT c.name, c.bases, fi.path, c.line_start
FROM classes c JOIN files fi ON c.file_id = fi.id
WHERE c.bases LIKE '%DetObjectFunc%'
ORDER BY fi.path;

-- Find methods of a class
SELECT name, line_start, substr(signature, 1, 50) as sig
FROM functions WHERE class_name = 'ROIFunc'
ORDER BY line_start;

-- Find callers of addFunc
SELECT c.caller_function, fi.path, c.line
FROM calls c JOIN files fi ON c.file_id = fi.id
WHERE c.callee_name = 'addFunc'
ORDER BY fi.path LIMIT 20;

-- Find all analysis functions
SELECT f.name, fi.path, f.line_start
FROM functions f JOIN files fi ON f.file_id = fi.id
WHERE f.name = 'process' AND f.class_name IS NOT NULL
ORDER BY fi.path;
```

## Key Class Hierarchy

```
DetObjectFunc (base)           # All analysis functions
├── ROIFunc                    # Region of interest
├── projectionFunc             # 1D projections
├── rebinFunc                  # Rebinning
├── azimuthalBinning           # Radial averaging
├── dropletFunc                # Droplet detection
├── photonFunc/photon2/photon3 # Photon reconstruction
└── ... (30 subclasses total)

DetObjectContainer             # Area detector containers (LCLS2)
├── CameraObject
├── WaveformObject
└── GenericContainer
```

## Workflow

1. **Understand the question** - Is it about a specific function, workflow, or concept?
2. **Check documentation first** - Read the relevant `.agent_docs/` file
3. **Query the code index** - Find specific classes, methods, or call relationships
4. **Read source code** - Use the Read tool to view actual implementation
5. **Cross-reference Confluence** - Use `@confluence-doc` for official documentation

## Integration with Other Skills

- **@confluence-doc**: Query official LCLS Confluence documentation
- **@ask-lcls2**: For psana2/lcls2 code questions
- **@askcode**: For indexing OTHER repositories

## Key Reminders

- LCLS1 code is in `lcls1/`, LCLS2 code is in `lcls2/` subdirectories
- Common base classes are in `common/`
- Producer scripts are in `lcls1_producers/` and `lcls2_producers/`
- All DetObjectFunc subclasses must implement `process()` method
- Always show file paths relative to repo root for clarity
