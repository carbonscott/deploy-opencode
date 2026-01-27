# confluence-doc Migration Log

Migrated on 2026-01-27.

## Goal

Deploy the Confluence documentation pipeline to `$APP_TOOL/confluence-doc/` with automated hourly cron updates producing `$APP_DATA/confluence-doc/lcls-docs.db`. Move the existing DB from `$APP_DATA/lcls-docs.db` to the standard `$APP_DATA/<app-name>/` layout. Initialize the deployed directory as a git repo (source project is not one).

## Path variables

- `$APP_ROOT` = `/sdf/group/lcls/ds/dm/apps`
- `$APP_TOOL` = `$APP_ROOT/dev/tools`
- `$APP_DATA` = `$APP_ROOT/dev/data`

## Before / After

| Resource | Before | After |
|----------|--------|-------|
| Tool | Not deployed (source at `proj-confluence-llm/`) | `$APP_TOOL/confluence-doc/` (git repo) |
| Data | `$APP_DATA/lcls-docs.db` (flat) | `$APP_DATA/confluence-doc/lcls-docs.db` |
| Agent DB path | Points to `$APP_DATA/lcls-docs.db` | Points to `$APP_DATA/confluence-doc/lcls-docs.db` |
| Cron | None | Every hour on sdfcron001 |
| Old `$APP_DATA/lcls-docs.db` | Serving agents | Deleted after migration |

## What changed

### Source project (`/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/`)

Only agent/skill DB path updates:

| File | Change |
|------|--------|
| `.opencode/agents/confluence-doc.md` | Changed DB path to `$APP_DATA/confluence-doc/lcls-docs.db` (2 occurrences) |
| `.claude/skills/confluence-doc/SKILL.md` | Changed DB path to `$APP_DATA/confluence-doc/lcls-docs.db` (2 occurrences) |

No changes to the Python scripts — they are already fully configurable via CLI arguments.

### Deployed tool (`$APP_TOOL/confluence-doc/`)

Created as a new git repo with a minimal file set (not a full copy of the source project):

| File | Source |
|------|--------|
| `confluence_to_markdown.py` | Copied from source (Confluence → markdown export) |
| `md_to_sql.py` | Copied from source (markdown → SQLite conversion) |
| `orchestrate_md_to_sql.py` | Copied from source (bulk markdown → SQLite orchestration) |
| `create_fts_index.py` | Copied from source (FTS5 index creation) |
| `pyproject.toml` | New: uv project with dependencies |
| `env.sh` | New: auto-detect + env.local pattern |
| `scripts/confluence-cron.sh` | New: cron wrapper for full pipeline |
| `.gitignore` | New: excludes env.local, .venv, .uv-cache, *.db, confluence_export/, *.log |

Deployed-only (gitignored):

| File | Value |
|------|-------|
| `env.local` | Sets `CONFLUENCE_DOC_DATA_DIR`, `CONFLUENCE_TOKEN_FILE` |
| `.venv/` | Created with uv (Python 3.11) |

### Deployed agent

| File | Change |
|------|--------|
| `agents/confluence-doc.md` | Changed DB path from `$APP_DATA/lcls-docs.db` to `$APP_DATA/confluence-doc/lcls-docs.db` (2 occurrences) |

### Deploy-opencode documentation

- `CLAUDE.md` — added confluence-doc to directory structure, source-deploy mapping, data update commands, key config details, agent/skill locations
- `docs/notes.md` — changed confluence-doc section from "Current/Future Path" to "Source/Deployed Path"

## Steps taken

1. Created `$APP_TOOL/confluence-doc/` with scripts/ subdirectory
2. Copied 4 Python scripts from source
3. Created `pyproject.toml` with dependencies (atlassian-python-api, pypandoc, pypandoc-binary, pyyaml)
4. Created `env.sh` with auto-detect + env.local pattern
5. Created `scripts/confluence-cron.sh` (cron wrapper)
6. Created `.gitignore`
7. Initialized git repo, initial commit
8. Created venv with uv (Python 3.11), installed dependencies
9. Copied Confluence token to `$APP_ROOT/dev/env/confluence.dat` (chmod 600)
10. Created `env.local` with deployed paths and token file location
11. Created `$APP_DATA/confluence-doc/`, copied existing DB
12. Ran initial full pipeline (export → SQL → FTS5)
13. Updated deployed agent DB path (2 occurrences)
14. Updated source agent and skill DB paths
15. Enabled cron on sdfcron001 (`0 * * * *`)
16. Deleted old `$APP_DATA/lcls-docs.db`
17. Updated `CLAUDE.md`, `docs/notes.md`, created this migration log

## Key design decisions

### Minimal file set (not a full copy)

The source project (`proj-confluence-llm/`) contains development artifacts (MCP server, starter scripts, token files, export logs, markdown exports, development docs) that are not needed for deployment. We copied only the 4 Python scripts that form the pipeline, plus created new infrastructure files (pyproject.toml, env.sh, cron wrapper, .gitignore).

### Git repo in deployed dir (not source)

The source project is not a git repo and contains messy development artifacts. Rather than initializing git there, we created a clean git repo in the deployed directory with only the minimal files. This gives us version tracking for the deployed code.

### `pypandoc-binary` for pandoc dependency

`pypandoc` requires system pandoc, which isn't available on SDF. The `pypandoc-binary` PyPI package bundles pre-built pandoc binaries (32.5 MiB) — installed via uv alongside `pypandoc`. No system package manager needed.

### env.sh / env.local pattern

Same pattern as lcls-catalog, daq-logs, and elog-copilot: `env.sh` auto-detects the project directory and sources `env.local` for deployment-specific overrides. The deployed repo stays git-clean.

### Confluence token stored in shared env directory

Token stored at `$APP_ROOT/dev/env/confluence.dat` (alongside `kerberos.dat`), with 600 permissions. Referenced in `env.local` as `CONFLUENCE_TOKEN_FILE`.

### Hourly cron frequency

The pipeline exports all pages from the PSDM Confluence space, converts to SQLite, and rebuilds the FTS5 index. The DB is small (~2.7M), and the export uses `--resume` to avoid re-downloading unchanged pages.

## Differences from other migrations

| Aspect | confluence-doc | lcls-catalog | daq-logs | elog-copilot |
|--------|---------------|-------------|----------|-------------|
| Source is git repo | No | Yes | Yes (GitHub) | Yes (GitHub) |
| Deployed as | New git repo (minimal files) | rsync copy | git clone | rsync copy |
| Compute | Network I/O + pandoc conversion | Slurm sbatch | Network I/O + SQLite | Network I/O |
| Data format | SQLite DB (2.7M) | Parquet (5.9G) | SQLite DB (2.2G) | SQLite DB (~1.3G) |
| Update frequency | Every hour | Cron (sbatch) | Every 5 min | Every 6 hours |
| Auth | Confluence API token (file) | None | None | Kerberos (password file) |
| Data management | Overwrite in place | Overwrite in place | Append | Symlink to latest |
| System deps | pandoc (via pypandoc-binary) | None | None | Kerberos (conda) |

## Files that did NOT need changes

- `confluence_to_markdown.py` — already fully configurable via CLI args
- `md_to_sql.py` — standalone, no hardcoded paths
- `orchestrate_md_to_sql.py` — imports from `md_to_sql`, CLI-driven
- `create_fts_index.py` — standalone, no hardcoded paths
