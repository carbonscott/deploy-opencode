---
name: lcls-catalog
description: "Assists with LCLS experiment data catalog operations: querying file metadata with SQL, folder sizes, finding files by pattern/size, listing directory contents, and catalog snapshots. Use when the user asks about LCLS data, experiment files, catalog queries, or running lcls-catalog/lcat commands."
---

# lcls-catalog Skill

You are helping the user work with `lcls-catalog`, a CLI tool for browsing and searching LCLS experiment data metadata stored as Parquet snapshots.

## Environment Setup

Every bash command must source env.sh before calling `lcat`, because each command runs in a fresh shell. Always combine them with `&&`:

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/lcls-catalog/env.sh && lcat <command> [args...]
```

This loads `LCLS_CATALOG_APP_DIR`, `CATALOG_DATA_DIR`, and the `lcat` shell function.

## Use `lcat` to Answer Questions

Always use `lcat` commands instead of Linux commands like `find` or `ls`. The catalog contains indexed metadata for all experiment files, so `lcat` is faster and more complete than filesystem commands.

Prefer `lcat query "<SQL>"` over other subcommands — SQL gives you the most flexibility for filtering, aggregation, and joins. Use `lcat find`, `lcat ls`, etc. only for simple lookups where a one-liner is clearer than SQL.

For any question about folder or directory sizes ("largest folders", "how big is X/xtc", "which experiments use the most space"), query the `dirs` table, not `files`. It is precomputed and answers in under a second; aggregating `files` by folder can hit the limits below.

## Limits: a stopped query is final

`lcat` runs on shared interactive nodes, so every query is capped at 8 GB of memory, 8 threads and 90 seconds until the first rows. A query that hits a cap prints `lcat: query stopped: ...` and exits with code 3. When that happens:

- Do not retry the same query, run it in the background, poll it, wrap it in `timeout`, or tell the user you will wait longer. It will stop the same way.
- Do not raise the limits (`LCAT_MEMORY_LIMIT`, `LCAT_TIMEOUT`, ...) on an interactive node: that is what degrades the node for everyone.
- Rewrite it smaller: use `dirs` for folder sizes; filter early with `WHERE experiment = '<exp>'` or `WHERE parent_path LIKE '/sdf/data/lcls/ds/<hutch>/<exp>/%'`; aggregate to fewer groups (`GROUP BY experiment`, not `GROUP BY path`); add `LIMIT` when listing rows.
- If it cannot be made smaller, tell the user it is too big for an interactive query and that it can run as a Slurm batch job with higher `LCAT_*` limits.

| Command | `lcat` usage |
|---------|-------------|
| stats | `lcat stats` |
| find | `lcat find "<pattern>" [options]` |
| query | `lcat query "<SQL>"` |
| ls | `lcat ls <path> [--dirs]` |
| tree | `lcat tree <path> [--depth N]` |
| snapshots | `lcat snapshots [-e <exp>]` |

The `lcat` wrapper automatically supplies `$CATALOG_DATA_DIR` for read commands.

`snapshot`, `consolidate` and `refresh` write to the shared catalog. They are run by the nightly indexing job and its maintainer; do not run them unless the user explicitly asks to maintain the catalog.

## Command Reference

### ls - List files or directories

```bash
lcat ls <path>           # List files
lcat ls <path> --dirs    # List subdirectories with counts/sizes
```

Options: `--on-disk` (only files currently on disk).

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
| `--no-symlinks` | Exclude symlinks |

### tree - Directory tree

```bash
lcat tree <path> --depth 3
```

### stats - Catalog statistics

```bash
lcat stats
```

Shows total files, on-disk count, removed count, and total sizes.

### query - SQL queries

```bash
lcat query "<SQL>"
```

Table name: `files`. Available columns:

| Column | Type | Notes |
|--------|------|-------|
| `path` | text | Full file path |
| `parent_path` | text | Parent directory |
| `filename` | text | File name only |
| `size` | integer | Size in bytes |
| `mtime` | integer | Unix epoch seconds |
| `owner` | text | Numeric uid as text, e.g. `'12345'` (find it with `id -u <user>`), not a username |
| `group_name` | text | Numeric gid as text |
| `permissions` | integer | `st_mode` bits |
| `checksum` | text | SHA-256 (if computed) |
| `experiment` | text | Experiment name |
| `run` | integer | Run number parsed from `run<N>` in the path, else NULL |
| `on_disk` | boolean | Currently on disk? |
| `indexed_at` | text | When indexed |

**Date filtering**: `mtime` is epoch seconds. Convert with `date -d "2026-01-01" +%s`.

Table `dirs` has one row per directory, counting files currently on disk:

| Column | Type | Notes |
|--------|------|-------|
| `experiment` | text | Experiment name |
| `path` | text | Directory path |
| `depth` | integer | Number of path components |
| `level` | integer | 0 = experiment root, 1 = `xtc/`, `hdf5/`, `scratch/`, ... |
| `files`, `bytes` | integer | Recursive totals: everything under the directory |
| `direct_files`, `direct_bytes` | integer | Files directly in the directory |
| `newest_mtime` | integer | Newest file under it, epoch seconds |

Common queries:
```sql
-- Files by experiment
SELECT experiment, COUNT(*) as files, SUM(size)/1e12 as tb FROM files GROUP BY experiment ORDER BY tb DESC

-- Largest files
SELECT path, size/1e9 as gb FROM files ORDER BY size DESC LIMIT 20

-- Files modified after a date
SELECT path, size/1e9 as gb FROM files WHERE mtime >= 1767225600 ORDER BY mtime DESC LIMIT 20

-- Ten largest xtc folders
SELECT path, bytes/1e12 AS tb, files FROM dirs WHERE path LIKE '%/xtc' ORDER BY bytes DESC LIMIT 10

-- Largest top-level folders of one experiment
SELECT path, bytes/1e12 AS tb FROM dirs WHERE experiment = 'mfx101591026' AND level = 1 ORDER BY bytes DESC
```

### snapshots - List snapshot files

```bash
lcat snapshots                # All snapshots
lcat snapshots -e <experiment>  # Filter by experiment
```

## LCLS Data Structure

LCLS data is organized as `/sdf/data/lcls/ds/<hutch>/<experiment>/`. The catalog indexes the amo, cxi, mec, mfx, tmo, ued, rix, xcs, det, mob and prj trees nightly. xpp is not indexed yet, so for xpp use the filesystem directly.

## Key Reminders

- Pattern syntax uses `%` (SQL LIKE), not `*` (shell glob)
- Always use `-H` flag when showing file sizes to the user
- Use `dirs` (with `level` / `path` filters) for directory sizes rather than `tree`, which re-scans the catalog once per directory
- The index is rebuilt nightly, so files written today may be missing; if a query comes back suspiciously empty for something you know exists, check with `ls`
