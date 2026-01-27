# lcls-catalog Migration Log

Migrated on 2026-01-26.

## Goal

Standardize the deployed data path from `$APP_DATA/lcls_parquet/` to `$APP_DATA/lcls-catalog/lcls_parquet/`, matching the `$APP_DATA/<app-name>/` convention. Also removed hardcoded paths from the source repo to make it portable.

## Path variables

- `$APP_ROOT` = `/sdf/group/lcls/ds/dm/apps`
- `$APP_TOOL` = `$APP_ROOT/dev/tools`
- `$APP_DATA` = `$APP_ROOT/dev/data`

## Before / After

| Resource | Before | After |
|----------|--------|-------|
| Deployed data | `$APP_DATA/lcls_parquet/` | `$APP_DATA/lcls-catalog/lcls_parquet/` |
| Deployed tool | `$APP_TOOL/lcls-catalog/` | `$APP_TOOL/lcls-catalog/` (unchanged) |
| Cron entry target | Source repo path | Deployed tool path |

## What changed

### Source repo (`/sdf/scratch/users/c/cwang31/proj-lcls-catalog/`)

Fixed hardcoded paths to make the repo portable:

| File | Change |
|------|--------|
| `env.sh` | `UV_CACHE_DIR` now uses `$LCLS_CATALOG_APP_DIR/.uv-cache` instead of a hardcoded path |
| `scripts/catalog_index.sbatch` | Removed hardcoded `#SBATCH --output` path (set to `slurm_%j.log` as fallback; actual path passed via `catalog-cron.sh`) |
| `scripts/catalog_index.sbatch` | `PROJECT_DIR` now uses `$LCLS_CATALOG_APP_DIR` instead of a hardcoded path |
| `scripts/catalog-cron.sh` | `sbatch` call now passes `--output="$CATALOG_DATA_DIR/slurm_%j.log"` on the command line |
| `scripts/catalog-cron.sh` | Log file echo now uses `$CATALOG_DATA_DIR` instead of a hardcoded path |
| `SKILLS.md` | Documentation table uses "Set in `env.sh`" instead of hardcoded paths |

### Deployed tool (`$APP_TOOL/lcls-catalog/`)

After copying the source repo, only `env.sh` was updated:

| Variable | Value |
|----------|-------|
| `LCLS_CATALOG_APP_DIR` | `/sdf/group/lcls/ds/dm/apps/dev/tools/lcls-catalog` |
| `CATALOG_DATA_DIR` | `/sdf/group/lcls/ds/dm/apps/dev/data/lcls-catalog/lcls_parquet/` |
| `UV_CACHE_DIR` | Resolves via `$LCLS_CATALOG_APP_DIR/.uv-cache` |

### Deploy-opencode documentation

- `CLAUDE.md` — updated directory structure table, source-deploy mapping, and rsync command
- `docs/notes.md` — changed lcls-catalog section headers from "Current/Future Path" to "Source/Deployed Path"

## Steps taken

1. Fixed hardcoded paths in the source repo (see table above)
2. Disabled cron on sdfcron001
3. Copied source repo to `$APP_TOOL/lcls-catalog/` (rsync, excluding `.git`, `.uv-cache`, `__pycache__`)
4. Updated deployed `env.sh` with deployed-specific paths
5. Fresh data copy from source to `$APP_DATA/lcls-catalog/lcls_parquet/`
6. Verified `lcat stats` and `lcat find` work with new paths
7. Re-enabled cron on sdfcron001 (now pointing to deployed tool path)
8. Updated `CLAUDE.md` and `docs/notes.md`
9. Deleted old `$APP_DATA/lcls_parquet/`

## Key design decision

`#SBATCH --output` directives don't expand shell variables (they're parsed by Slurm before the script runs). Instead of hardcoding a path there, we pass `--output` on the `sbatch` command line in `catalog-cron.sh`, which overrides the directive. The sbatch file keeps `--output=slurm_%j.log` as a safe fallback for manual submission.

## Files that did NOT need changes

- `$APP_ROOT/dev/opencode/skills/lcls-catalog/SKILL.md` — sources `env.sh` and uses variables
- `scripts/run_catalog_index.sh` — already uses `$CATALOG_DATA_DIR`
- `CRON.md`, `OPERATION.md` — already use `$CATALOG_DATA_DIR`

---

## Follow-up: Separating config from code

### Problem

After the migration, the deployed repo had a dirty `env.sh` — three lines differed from git (hardcoded deployed paths for `LCLS_CATALOG_APP_DIR`, `CATALOG_DATA_DIR`, and comment). This meant:

- `git pull` in the deployed repo would cause merge conflicts
- The deployed repo could never have a clean working tree
- A `dev` branch wouldn't help either — the conflict is between **configuration values**, not feature code. Both branches would need different paths in the same file, creating a permanent merge conflict.

### Solution: auto-detect + `env.local`

This is the same pattern as `.env` files in web projects: tracked code provides defaults, a gitignored local file provides overrides.

Changes to `env.sh` (commit `6d24c82`):

1. **Auto-detect `LCLS_CATALOG_APP_DIR`** from the script's own location:
   ```bash
   export LCLS_CATALOG_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   ```
   This eliminates the need to hardcode the project path at all.

2. **Source `env.local` if it exists** for deployment-specific overrides:
   ```bash
   if [[ -f "$LCLS_CATALOG_APP_DIR/env.local" ]]; then
       source "$LCLS_CATALOG_APP_DIR/env.local"
   fi
   ```

3. **Added `env.local` to `.gitignore`** so it never gets committed.

### Deployed `env.local`

The deployed installation has one file (`$APP_TOOL/lcls-catalog/env.local`):
```bash
# Deployed lcls-catalog configuration
# This file is gitignored — local to this installation only.
export CATALOG_DATA_DIR=/sdf/group/lcls/ds/dm/apps/dev/data/lcls-catalog/lcls_parquet/
```

### Result

- Source repo: no `env.local`, uses dev defaults. Git clean.
- Deployed repo: `env.local` overrides `CATALOG_DATA_DIR`. Git clean.
- Future updates: just `git pull` in the deployed repo — no conflicts.

### Lesson for other tools

When deploying a tool to `$APP_TOOL/<app>/` that has environment-specific config:

1. Auto-detect the tool's own path (don't hardcode it)
2. Put deployment-specific values in a gitignored `env.local`
3. Have `env.sh` source `env.local` after setting defaults
4. Only `CATALOG_DATA_DIR` (or equivalent data path) should need overriding — the tool path is auto-detected
