# elog-copilot Migration Log

Migrated on 2026-01-26.

## Goal

Deploy the `elogfetch` tool to `$APP_TOOL/elog-copilot/` and set up automated cron updates producing `$APP_DATA/elog-copilot/elog-copilot.db`. Update the deployed agent to use the new DB path. Keep the old prod DB intact (it serves another application).

## Path variables

- `$APP_ROOT` = `/sdf/group/lcls/ds/dm/apps`
- `$APP_TOOL` = `$APP_ROOT/dev/tools`
- `$APP_DATA` = `$APP_ROOT/dev/data`

## Before / After

| Resource | Before | After |
|----------|--------|-------|
| Tool | Not deployed (source at `fetch-elog` repo) | `$APP_TOOL/elog-copilot/` |
| Data | `$APP_ROOT/prod/appdata/elogCoPilot/experiment_database_sdf.db` | `$APP_DATA/elog-copilot/elog-copilot.db` (symlink) |
| Agent DB path | Points to prod path | Points to `$APP_DATA/elog-copilot/elog-copilot.db` |
| Cron | None | Every 6 hours on sdfcron001 |
| Old prod DB | Serving another app | Untouched, still serving that app |

## What changed

### Source repo (`/sdf/data/lcls/ds/prj/prjcwang31/results/fetch-elog/`)

Added deployment support (commit `a6af746`):

| File | Change |
|------|--------|
| `env.sh` | New: auto-detect `ELOG_COPILOT_APP_DIR`, set `UV_PYTHON`, `UV_CACHE_DIR`, `ELOG_COPILOT_DATA_DIR`; sources `env.local` for overrides |
| `scripts/elog-cron.sh` | New: cron wrapper with Kerberos password-file auth, incremental update, symlink management, cleanup (keep 8 most recent DBs) |
| `.gitignore` | Added `env.local` and `.uv-cache/` |

### Deployed tool (`$APP_TOOL/elog-copilot/`)

rsync'd from source (excluding `.git`, `.venv`, `*.db`, `.env`, caches). Then:

| File | Value |
|------|-------|
| `env.local` | Sets `ELOG_COPILOT_DATA_DIR`, `ELOG_COPILOT_DEPLOY_PATH`, `KRB5_PASSWORD_FILE`, `KRB5_PRINCIPAL` |
| `.venv/` | Created with `--system-site-packages` (inherits `krtc` from conda) |

### Deployed agent

| File | Change |
|------|--------|
| `agents/elog-copilot.md` | Changed DB path from prod to `$APP_DATA/elog-copilot/elog-copilot.db` (3 occurrences) |

### Deploy-opencode documentation

- `CLAUDE.md` — added elog-copilot to directory structure, source-deploy mapping, config details, agent/skill locations
- `docs/notes.md` — changed elog-copilot section from "Current/Future Path" to "Source/Deployed Path"

## Steps taken

1. Created `env.sh` and `scripts/elog-cron.sh` in source repo, updated `.gitignore`
2. Committed source changes (`a6af746`)
3. rsync'd source to `$APP_TOOL/elog-copilot/`
4. Created `env.local` with deployed-specific paths and Kerberos config
5. Set up venv with `--system-site-packages`, installed `elogfetch`
6. Created `$APP_DATA/elog-copilot/`, seeded with existing `elog_2026_0122_1439.db`
7. Ran initial incremental update → produced `elog_2026_0126_2155.db` (1,794 experiments)
8. Created symlink: `elog-copilot.db` → `elog_2026_0126_2155.db`
9. Updated deployed agent to point to new DB path (3 occurrences)
10. Updated source agent copy to match
11. Enabled cron on sdfcron001 (`0 */6 * * *`)
12. Updated `CLAUDE.md` and `docs/notes.md`

## Key design decisions

### Symlink instead of copy for canonical DB

`elog-copilot.db` is a symlink to the latest `elog_*.db` file (e.g., `elog_2026_0126_2155.db`). This avoids a 1.3G copy on each cron run. The cron script updates the symlink atomically with `ln -sf`.

### Kerberos via password file

MIT `kinit` on SDF reads passwords from stdin. The cron script's `ensure_kerberos()` checks for a valid ticket first (`klist -s`); if none exists, it runs `kinit $KRB5_PRINCIPAL < $KRB5_PASSWORD_FILE`. The password file (`/sdf/group/lcls/ds/dm/apps/dev/env/kerberos.dat`) has 600 permissions, readable only by cwang31. Tickets last ~25 hours; cron runs every 6 hours.

**Status at migration time**: The initial incremental update (step 7) succeeded using a pre-existing Kerberos ticket from an earlier manual `kinit` — so the password-file path was not exercised during migration. The first real test will be when cron fires without a pre-existing ticket. If it fails, errors will appear in `$APP_DATA/elog-copilot/cron.log`. Fallback: manually run `kinit cwang31@SLAC.STANFORD.EDU`.

### Built-in DB cleanup

The cron script keeps only the 8 most recent `elog_*.db` files and deletes older ones. At ~1.3G each, this limits disk usage to ~10G.

### env.sh / env.local pattern

Same pattern as lcls-catalog: `env.sh` auto-detects the project directory and sources `env.local` for deployment-specific overrides. The deployed repo stays git-clean.

## Files that did NOT need changes

- `src/elogfetch/` — already fully configurable via CLI args and env vars
- `examples/periodic_update.sh` — still works standalone; `elog-cron.sh` supersedes it for deployed use
- `pyproject.toml` — no changes needed

## Differences from lcls-catalog migration

| Aspect | lcls-catalog | elog-copilot |
|--------|-------------|-------------|
| Compute | Slurm sbatch job | Direct CLI run (network I/O, not compute) |
| Data format | Parquet files (5.9G dir) | SQLite DB (~1.3G file) |
| Update mechanism | `catalog-cron.sh` → sbatch | `elog-cron.sh` → elogfetch directly |
| Canonical name | Directory of parquet files | Symlink to latest timestamped DB |
| Auth | None | Kerberos (password file) |
| Cleanup | N/A (overwritten in place) | Keep 8 most recent, delete older |
| `.git` in deployed copy | Excluded (rsync `--exclude='.git'`) | Included — deployed copy is a git repo |

### Why the deployed copy includes `.git`

The lcls-catalog migration excluded `.git` from the rsync. For elog-copilot we initially did the same, but discovered that `/sdf/group/lcls/ds/dm/` is itself a git repository. Running `git status` inside the deployed tool directory (which lacked its own `.git`) caused git to walk up the tree and find that parent repo, showing unrelated modified files (`bin/hsi_irods.sh`, etc.) — confusing and misleading.

Including `.git` in the deployed copy solves this: git finds the tool's own `.git` first. Additional benefits:
- `git pull` to update the deployed tool (instead of manual rsync)
- `git log` shows exactly what version is deployed

The `env.local` + `.gitignore` pattern ensures the deployed working tree stays clean — `env.local`, `.uv-cache/`, lock files, and `*.db` are all gitignored.

**Lesson for other tools**: If deploying under `/sdf/group/lcls/ds/dm/apps/`, include `.git` in the rsync to avoid inheriting the parent repo's context.
