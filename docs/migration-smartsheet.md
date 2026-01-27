# smartsheet Migration Log

Migrated on 2026-01-27.

## Goal

Deploy the `smartsheet-db-scripts` tool to `$APP_TOOL/smartsheet/` and set up daily cron sync producing `$APP_DATA/smartsheet/closeout_notes.db`. Create an agent definition for querying experiment closeout data. Deprecate the old source project at `proj-smartsheet`.

## Path variables

- `$APP_ROOT` = `/sdf/group/lcls/ds/dm/apps`
- `$APP_TOOL` = `$APP_ROOT/dev/tools`
- `$APP_DATA` = `$APP_ROOT/dev/data`

## Before / After

| Resource | Before | After |
|----------|--------|-------|
| Tool | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-smartsheet/` (local clone) | `$APP_TOOL/smartsheet/` (git clone) |
| Data | `proj-smartsheet/data/closeout_notes.db` (36 MB) | `$APP_DATA/smartsheet/closeout_notes.db` |
| API key | `proj-smartsheet/.env` (local file) | `$APP_ROOT/dev/env/smartsheet.dat` (shared key file) |
| Agent | None | `$APP_ROOT/dev/opencode/agents/smartsheet.md` |
| Cron | None | Daily at 3am on sdfcron001 |
| Old source | Active | Deprecated |

## What changed

### Source repo (`git@github.com:carbonscott/smartsheet-db-scripts.git`)

Added deployment support (commit `7c62c4b`):

| File | Change |
|------|--------|
| `env.sh` | New: auto-detect `SMARTSHEET_APP_DIR`, set `UV_CACHE_DIR`, `SMARTSHEET_DATA_DIR`; sources `env.local` for overrides; reads API key from `SMARTSHEET_KEY_FILE` |
| `scripts/pull.py` | Added `get_data_dir()` using `SMARTSHEET_DATA_DIR` env var; `--db-path` default and `attachments_dir` now use it |
| `scripts/pull_all.sh` | Sources `env.sh`, passes `--db-path` to each `pull.py` call, uses `$SMARTSHEET_DATA_DIR` for sqlite3 summary |
| `scripts/smartsheet-cron.sh` | New: cron wrapper that sources `env.sh` and runs `pull_all.sh`, logging to `$SMARTSHEET_DATA_DIR/cron.log` |
| `.gitignore` | Added `env.local` and `.uv-cache/` |

### Deployed tool (`$APP_TOOL/smartsheet/`)

Git clone of the repo. Added:

| File | Value |
|------|-------|
| `env.local` | Sets `SMARTSHEET_DATA_DIR` and `SMARTSHEET_KEY_FILE` |
| `.venv/` | Created with `uv venv`, deps installed via `uv pip install -r requirements.txt` |

### Deployed agent

| File | Change |
|------|--------|
| `agents/smartsheet.md` | New: query helper for experiment closeout data with full schema, example queries |

### Deploy-opencode documentation

- `CLAUDE.md` — added smartsheet to directory structure, source-deploy mapping, data update commands, config details, agent locations
- `docs/notes.md` — changed smartsheet section from "Current/Future Path" to "Source/Deployed Path"

## Steps taken

1. Cloned repo to `$APP_TOOL/smartsheet/`
2. Created `env.sh` with auto-detect + env.local pattern
3. Modified `scripts/pull.py` to use `SMARTSHEET_DATA_DIR` env var for db-path and attachments
4. Modified `scripts/pull_all.sh` to source env.sh and pass `--db-path`
5. Created `scripts/smartsheet-cron.sh` cron wrapper
6. Updated `.gitignore` with `env.local`, `.uv-cache/`
7. Committed and pushed (`7c62c4b`)
8. Created API key file at `$APP_ROOT/dev/env/smartsheet.dat` (copied from old `.env`)
9. Created `env.local` with deployed paths
10. Created venv with `uv venv && uv pip install -r requirements.txt`
11. Created `$APP_DATA/smartsheet/`, seeded with existing 36 MB DB (387 sheets)
12. Verified: single-sheet pull succeeded, DB queried correctly
13. Created agent definition at `agents/smartsheet.md`
14. Updated `CLAUDE.md` and `docs/notes.md`

## Key design decisions

### Git clone as canonical repo

Unlike the other migrations where a separate source project exists, smartsheet uses the git clone at `$APP_TOOL/smartsheet/` as the canonical working copy. The old `proj-smartsheet` directory is deprecated. Updates are done via `git pull`.

### API key in shared key file

The Smartsheet personal access token lives at `$APP_ROOT/dev/env/smartsheet.dat` (600 permissions), following the same pattern as `kerberos.dat`. The `env.sh` reads it via `SMARTSHEET_KEY_FILE` and exports `SMARTSHEET_API_KEY`. The Python code's `load_dotenv()` won't override the already-set env var.

### env.sh + env.local pattern

Same pattern as all other tools. `env.sh` auto-detects `SMARTSHEET_APP_DIR`, sets defaults, sources `env.local`. Only `SMARTSHEET_DATA_DIR` and `SMARTSHEET_KEY_FILE` need overriding in the deployed `env.local`.

### Instrument column caveat

The `instrument` column in `sheets` is all set to 'XCS' (the `--instrument` default in `pull.py`). This is because `pull_all.sh` passes `--sheet-id` without `--instrument`, so all sheets get the default. To find the actual instrument, parse `sheet_name` (e.g., `WHERE sheet_name LIKE '%CXI%'`). The agent definition documents this.

## Files that did NOT need changes

- `schema.sql` — no changes needed
- `scripts/discover.py` — standalone discovery script, no hardcoded paths
- `explore_smartsheet.py` — exploration script
- `tests/test_pull.py` — tests
- `requirements.txt` — dependencies unchanged

## Differences from other migrations

| Aspect | smartsheet | daq-logs | elog-copilot | lcls-catalog |
|--------|-----------|----------|-------------|-------------|
| Deploy method | Git clone | Git clone | rsync + .git | rsync (no .git) |
| Auth | API token (key file) | None | Kerberos (password file) | None |
| Data format | SQLite DB (36 MB) | SQLite DB (2.2 GB) | SQLite DB (~1.3 GB) | Parquet files (5.9 GB) |
| Cron frequency | Daily | Every 5 min | Every 6 hours | Slurm sbatch |
| Source project | Deprecated | Active | Active | Active |
| Canonical copy | Deployed clone | Source + deployed clone | Source | Source |
