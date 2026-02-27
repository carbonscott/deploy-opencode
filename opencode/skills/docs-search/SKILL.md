---
name: docs-search
description: Strategy guide for searching local documentation collections. Use when users ask questions that can be answered from local docs, need to search a docs folder, or want to index documentation.
---

# Searching Documentation Collections

## Pick the right tool

| Goal | Tool | When to use |
|------|------|-------------|
| Discover relevant files in a large doc tree | `docs-index search` | Don't know which files are relevant yet; need ranked results across hundreds/thousands of docs |
| Find exact string or regex pattern | `Grep` | Know what you're looking for (function name, error message, specific term) |
| Browse directory structure / find files by name | `Glob` | Exploring what docs exist, filtering by extension or naming pattern |
| Read a specific document | `Read` | Already identified the file to examine |

Use `docs-index search` for **discovery**, then `Read` the top results. Use `Grep` when you need **precision** on a known pattern.

## Workflow

1. **Check for index:** look for `<docs_root>/search.db`
2. **If missing → auto-index:** run `docs-index index <docs_root> --incremental` and inform the user (e.g. "Building search index for the first time...")
3. **Search:** run `docs-index search <docs_root> "<query>" --limit N`
4. **Read** the returned file paths to answer the question
5. **Refine** with `Grep` or additional searches if initial results are insufficient

## docs-index CLI reference

### Installation

The script is deployed at `/sdf/group/lcls/ds/dm/apps/dev/bin/docs-index`. Requires `uv` (no other dependencies). If `docs-index` is not on PATH:

```bash
export PATH="/sdf/group/lcls/ds/dm/apps/dev/bin:$PATH"
```

Verify: `docs-index --help`

### Subcommands

```bash
docs-index index <docs_root> [--incremental] [--ext EXT ...]
docs-index search <docs_root> <query> [--limit N]
docs-index info <docs_root>
```

**Defaults:** extensions `md rst txt py`, limit `10`. Database: `<docs_root>/search.db`.

### FTS5 query syntax

| Pattern | Example | Meaning |
|---------|---------|---------|
| Simple term | `autograd` | Match token anywhere |
| Phrase | `"loss function"` | Exact phrase |
| Boolean OR | `adam OR sgd` | Either term (AND is implicit default) |
| Prefix | `optim*` | Prefix match |
| Combined | `"learning rate" optimizer OR scheduler` | Phrase + boolean |
