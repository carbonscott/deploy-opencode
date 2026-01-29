---
name: lcls-catalog
description: "Assists with LCLS experiment data catalog operations: indexing files with snapshots, querying metadata with SQL, finding files by pattern/size, listing directory contents, and managing catalog snapshots. Use when the user asks about LCLS data, experiment files, catalog queries, or running lcls-catalog/lcat commands."
---

# lcls-catalog Skill

Help users work with `lcls-catalog`, a CLI tool for browsing and searching LCLS experiment data metadata stored as Parquet snapshots.

## Environment Setup

Every bash command must source env.sh before calling `lcat`, because each command runs in a fresh shell:

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/lcls-catalog/env.sh && lcat <command> [args...]
```

This loads `LCLS_CATALOG_APP_DIR`, `CATALOG_DATA_DIR`, and the `lcat` shell function.

## Use `lcat` to Answer Questions

Always use `lcat` commands instead of Linux commands like `find` or `ls`. The catalog contains indexed metadata for all experiment files, so `lcat` is faster and more complete than filesystem commands.

Prefer `lcat query "<SQL>"` over other subcommands - SQL gives you the most flexibility for filtering, aggregation, and joins.

## Command Reference

| Command | Usage |
|---------|-------|
| stats | `lcat stats` |
| find | `lcat find "<pattern>" [options]` |
| query | `lcat query "<SQL>"` |
| ls | `lcat ls <path> [--dirs]` |
| tree | `lcat tree <path> [--depth N]` |
| snapshots | `lcat snapshots [-e <exp>]` |
| consolidate | `lcat consolidate [--archive <dir>]` |
| snapshot | `lcat snapshot <path> -e <experiment> [--workers N]` |

### snapshot - Index files before purge

```bash
lcat snapshot <path> -e <experiment> [--workers N] [--checksum]
```

Options: `--workers` (parallel, use 4-8 for large dirs), `--checksum` (SHA-256, slow).

### ls - List files or directories

```bash
lcat ls <path>           # List files
lcat ls <path> --dirs    # List subdirectories with counts/sizes
```

### find - Search for files

```bash
lcat find "<pattern>" [options]
```

Pattern uses SQL LIKE syntax: `%` is wildcard (not `*`).

| Option | Description |
|--------|-------------|
| `--size-gt SIZE` | Minimum size (e.g., `1GB`, `500MB`) |
| `--size-lt SIZE` | Maximum size |
| `-e, --experiment` | Filter by experiment |
| `--exclude PATTERN` | Exclude paths (repeatable) |
| `--on-disk` | Only files on disk |
| `--removed` | Only removed files |
| `--show-status` | Show [removed] tag |
| `-H` | Human-readable sizes |

### tree - Directory tree

```bash
lcat tree <path> --depth 3
```

### stats - Catalog statistics

```bash
lcat stats
```

### query - SQL queries

```bash
lcat query "<SQL>"
```

**Table: `files`**

| Column | Type | Notes |
|--------|------|-------|
| `path` | text | Full file path |
| `parent_path` | text | Parent directory |
| `filename` | text | File name only |
| `size` | integer | Size in bytes |
| `mtime` | integer | Unix epoch seconds |
| `owner` | text | File owner |
| `group_name` | text | File group |
| `permissions` | text | File permissions |
| `checksum` | text | SHA-256 (if computed) |
| `experiment` | text | Experiment name |
| `run` | text | Run identifier |
| `on_disk` | boolean | Currently on disk? |
| `indexed_at` | text | When indexed |

**Date filtering**: `mtime` is epoch seconds. Convert with `date -d "2026-01-01" +%s`.

Common queries:

```sql
-- Files by experiment
SELECT experiment, COUNT(*) as files, SUM(size)/1e12 as tb FROM files GROUP BY experiment ORDER BY tb DESC

-- Largest files
SELECT path, size/1e9 as gb FROM files ORDER BY size DESC LIMIT 20

-- Files modified after a date
SELECT path, size/1e9 as gb FROM files WHERE mtime >= 1767225600 ORDER BY mtime DESC LIMIT 20
```

### consolidate - Merge snapshots

```bash
lcat consolidate              # Merge and delete old files
lcat consolidate --archive /backup  # Merge and archive old files
```

### snapshots - List snapshot files

```bash
lcat snapshots                # All snapshots
lcat snapshots -e <experiment>  # Filter by experiment
```

## LCLS Data Structure

LCLS data is organized as `/sdf/data/lcls/ds/<hutch>/<experiment>/`. Hutches include: amo, cxi, mec, mfx, xcs, xpp, and others.

## Key Reminders

- Pattern syntax uses `%` (SQL LIKE), not `*` (shell glob)
- Always use `-H` flag when showing file sizes to the user
- For snapshot commands on large directories, suggest `--workers 4` or higher
- Base files are complete snapshots; delta files are incremental changes
- Run `consolidate` periodically to merge deltas into base files
