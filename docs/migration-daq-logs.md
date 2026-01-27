# daq-logs Migration Log

Migrated on 2026-01-26.

## Goal

Standardize the deployed data path from `$APP_DATA/daq_logs.db` to `$APP_DATA/daq-logs/daq_logs.db`, matching the `$APP_DATA/<app-name>/` convention. Deploy the tool scripts from the clean GitHub repo to `$APP_TOOL/daq-logs/`. Point the cron job at the deployed tool so it writes directly to the deployed data directory.

## Path variables

- `$APP_ROOT` = `/sdf/group/lcls/ds/dm/apps`
- `$APP_TOOL` = `$APP_ROOT/dev/tools`
- `$APP_DATA` = `$APP_ROOT/dev/data`

## Before / After

| Resource | Before | After |
|----------|--------|-------|
| Tool scripts | `/sdf/data/lcls/ds/prj/prjdat21/results/appdata/scripts/` (not a git repo) | `$APP_TOOL/daq-logs/` (git clone) |
| Database | `$APP_DATA/daq_logs.db` (manual copy) | `$APP_DATA/daq-logs/daq_logs.db` (cron-managed) |
| Raw log files | `/sdf/.../appdata/daq_logs/` | `$APP_DATA/daq-logs/daq_logs/` |
| Sync logs | `/sdf/.../appdata/sync_logs/`, `.../appdata/sync.log` | `$APP_DATA/daq-logs/sync_logs/`, `$APP_DATA/daq-logs/sync.log` |
| Cron entry | Points to `.../appdata/scripts/run_daq_log_sync.sh` | Points to `$APP_TOOL/daq-logs/scripts/run_daq_log_sync.sh` |
| Agent definition | DB path: `$APP_DATA/daq_logs.db` | DB path: `$APP_DATA/daq-logs/daq_logs.db` |

## What changed

### Source repo (`github.com/carbonscott/lcls-daq-browser-indexing-scripts`)

Commit `a9c5f3d`: Remove hardcoded paths, auto-detect dirs, support env.local

| File | Change |
|------|--------|
| `scripts/env.sh` | Auto-detect `DAQ_LOGS_APP_DIR` from script location; derive `DAQ_LOGS_DATA_DIR` from parent; source `env.local` for overrides |
| `scripts/run_daq_log_sync.sh` | Source `env.sh` for paths instead of hardcoding from script location |
| `scripts/sync-cron.sh` | Use `DAQ_LOGS_DATA_DIR` for `CRON_LOG` default |
| `scripts/ingest_daq_logs.py` | Sync error-handling improvements (try/except/finally with rollback and WAL cleanup) from running copy |
| `.gitignore` | Add `env.local` |

### Deployed tool (`$APP_TOOL/daq-logs/`)

Git clone of the clean repo. Only `scripts/env.local` was added:

| Variable | Value |
|----------|-------|
| `DAQ_LOGS_APP_DIR` | Auto-detected: `/sdf/group/lcls/ds/dm/apps/dev/tools/daq-logs/scripts` |
| `DAQ_LOGS_DATA_DIR` | Override via env.local: `/sdf/group/lcls/ds/dm/apps/dev/data/daq-logs` |

### Deploy-opencode documentation

- `CLAUDE.md` — updated directory structure table, source-deploy mapping, data update commands, key config details
- `docs/notes.md` — changed daq-logs section from "Current/Future Path" to "Source/Deployed Path"
- `agents/daq-logs.md` — updated DB path and contents description

## Steps taken

1. Cloned clean repo to `/sdf/scratch/users/c/cwang31/lcls-daq-browser-indexing-scripts/`
2. Updated `env.sh`, `run_daq_log_sync.sh`, `sync-cron.sh` for env.local pattern
3. Synced improved `ingest_daq_logs.py` from running copy
4. Added `env.local` to `.gitignore`
5. Committed and pushed (`a9c5f3d`)
6. Disabled cron on sdfcron001
7. Cloned to `$APP_TOOL/daq-logs/`
8. Created `$APP_TOOL/daq-logs/scripts/env.local` with deployed `DAQ_LOGS_DATA_DIR`
9. Created `$APP_DATA/daq-logs/`
10. Copied DB from source (2.2 GB)
11. Copied raw log files (13 GB via rsync)
12. Copied sync logs
13. Re-enabled cron via `sync-cron.sh enable`
14. Verified first cron cycle at 23:05 — completed successfully in 20 seconds
15. Updated agent `daq-logs.md`, `CLAUDE.md`, `docs/notes.md`
16. Deleted old `$APP_DATA/daq_logs.db`

## Design decisions

### env.sh + env.local pattern (same as lcls-catalog)

`env.sh` auto-detects `DAQ_LOGS_APP_DIR` from its own location and derives `DAQ_LOGS_DATA_DIR` as the parent directory (repo root). For deployments where tool and data live in different directories, `env.local` overrides `DAQ_LOGS_DATA_DIR`.

- Source repo: no `env.local` needed — defaults work (data alongside scripts)
- Deployed repo: `env.local` overrides `DAQ_LOGS_DATA_DIR` — git clean
- Future updates: just `git pull` in `$APP_TOOL/daq-logs/` — no conflicts

### Cron writes directly to deployed data

Unlike the previous setup where cron wrote to a source location and the DB was manually copied, the cron now writes directly to `$APP_DATA/daq-logs/`. No manual copy step needed.

### `ingest_daq_logs.py` divergence

The running copy at `appdata/scripts/` had improved error handling (try/except/finally with rollback and WAL checkpoint cleanup) that wasn't in the GitHub repo. This was synced back to the repo as part of the migration commit.

## Files that did NOT need changes

- `scripts/pull_daq_logs.sh` — uses arguments, no hardcoded paths
- `scripts/README.md`, `scripts/SYNC_IN_CRON.md` — documentation only
