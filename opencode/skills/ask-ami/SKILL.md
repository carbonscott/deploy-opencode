---
name: ask-ami
description: "Expert assistant for the AMI (Analysis Monitoring Interface) codebase. Use when users ask about AMI graph nodes, computation graphs, flowchart GUI, workers, collectors, managers, data sources, ZMQ communication, PV export, or LCLS-II online monitoring code."
---

# ask-ami Skill

You are helping the user explore and understand the AMI (Analysis Monitoring Interface) codebase — LCLS-II's online graphical analysis monitoring package. You have access to:

1. **Curated documentation** in `.agent_docs/` directory
2. **Code index database** (`.code-index.db`) with 2,114 functions, 351 classes
3. **Sphinx design docs** searchable via `docs-index`
4. **The actual source code** via the Read tool

## Repository Location

```
/sdf/group/lcls/ds/dm/apps/dev/software/ami/
```

## Documentation Index

Start by reviewing the relevant documentation file:

| Document | Path | Use When |
|----------|------|----------|
| **Codebase Overview** | `.agent_docs/codebase-overview.md` | Architecture, module structure, stats |
| **Quickstart** | `.agent_docs/guide-01-quickstart.md` | Entry points, running AMI, source config |
| **Architecture** | `.agent_docs/guide-02-architecture.md` | Distributed system, comm layer, messages |
| **Computation Graph** | `.agent_docs/guide-03-computation-graph.md` | Graph wrapper, node types, compilation |
| **Flowchart Nodes** | `.agent_docs/guide-04-flowchart-nodes.md` | GUI nodes, CtrlNode, library, custom nodes |
| **Data Sources** | `.agent_docs/guide-05-data-sources.md` | Source types, psana integration, detectors |
| **Code Index Queries** | `.agent_docs/askcode-queries.md` | SQL query examples for code index |

## Code Index Database

Query the code structure via sqlite3:

```bash
DB="/sdf/group/lcls/ds/dm/apps/dev/software/ami/.code-index.db"
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
-- Find all graph node subclasses
SELECT c.name, c.bases, fi.path, c.line_start
FROM classes c JOIN files fi ON c.file_id = fi.id
WHERE c.bases LIKE '%Transformation%'
ORDER BY fi.path;

-- Find flowchart node types
SELECT c.name, c.bases, fi.path
FROM classes c JOIN files fi ON c.file_id = fi.id
WHERE c.bases LIKE '%CtrlNode%'
ORDER BY fi.path;

-- Find methods of a class
SELECT name, line_start, substr(signature, 1, 50) as sig
FROM functions WHERE class_name = 'Graph'
ORDER BY line_start;

-- Find callers of a function
SELECT c.caller_function, fi.path, c.line
FROM calls c JOIN files fi ON c.file_id = fi.id
WHERE c.callee_name = 'compile'
ORDER BY fi.path LIMIT 20;
```

## Sphinx Design Docs (Full-Text Search)

AMI has Sphinx design documentation that can be searched:

```bash
docs-index search /sdf/group/lcls/ds/dm/apps/dev/software/ami/docs/source "<query>" --limit 5
```

Topics covered: computation_graph, data_source, worker, manager, store, local_collector.

## Key Architecture

```
Data Source (psana/random/static)
    │
    ▼
Workers (color: worker)            ← per-event Map/Filter nodes
    │
    ▼
Local Collectors (localCollector)  ← per-node reduction
    │
    ▼
Global Collector (globalCollector) ← final reduction
    │
    ▼
Manager                            ← graph management, client requests
    │
    ▼
Clients (GUI/Console/Monitor)      ← visualization, graph editing
```

## Workflow

1. **Understand the question** — Is it about graph nodes, data flow, GUI, deployment, or code-specific?
2. **Check documentation first** — Read the relevant `.agent_docs/` file
3. **Query the code index** — Find specific functions, classes, or call relationships
4. **Search Sphinx docs** — Use `docs-index search` for design documentation
5. **Read source code** — Use the Read tool to view actual implementation
6. **Cross-reference** — Use `@confluence-doc` for official LCLS documentation

## Integration with Other Skills

- **@confluence-doc**: Query official LCLS Confluence documentation
- **@ask-lcls2**: For psana2/lcls2 code questions (AMI uses psana as data source)
- **@askcode**: For indexing OTHER repositories

## Key Reminders

- AMI is a distributed system: Worker → Collector → Manager → Client
- Graph nodes have "colors" (worker/localCollector/globalCollector) assigned during compilation
- The flowchart GUI is built on PyQtGraph and uses Qt signals/slots
- Communication uses ZMQ pub/sub patterns
- Data sources wrap psana DataSource for LCLS detector data
- NetworkFoX is the underlying DAG execution engine
- Always show file paths relative to repo root for clarity
- After finding a function/class, use Read tool to show the actual code
