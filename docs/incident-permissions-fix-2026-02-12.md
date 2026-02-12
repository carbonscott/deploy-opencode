# Incident: Shared OpenCode Skills Inaccessible to Users

**Date:** 2026-02-12
**Impact:** Users in the ps-data group could not run lcls-catalog, askcode, smartsheet, or confluence-doc agent skills in the shared opencode deployment.

## Symptoms

Users reported that invoking skills like `@lcls-catalog` or `@askcode` failed. These skills source an `env.sh` file and run `uv run --project <tool-dir>`, which requires a working Python virtual environment.

## Root Causes

Three independent issues were found, all stemming from how files were initially copied/created in the shared deployment.

### 1. Venv Python symlinks pointed to deployer's home directory

When `uv` creates a virtual environment, it symlinks `.venv/bin/python` to the Python interpreter it manages, stored by default in `~/.local/share/uv/python/`. Since the deployer's `~/.local/` directory had `drwx------` permissions (owner-only), other users could not follow the symlink.

**Affected tools:**

| Tool | Venv Python target |
|------|--------------------|
| `tools/lcls-catalog/.venv` | `~cwang31/.local/share/uv/python/cpython-3.14.0.../bin/python3.14` |
| `tools/tree-sitter-db/.venv` | same |
| `tools/smartsheet/.venv` | same |
| `tools/confluence-doc/.venv` | `~cwang31/.local/share/uv/python/cpython-3.11.14.../bin/python3.11` |

`tools/elog-copilot/.venv` was not affected because it points to the shared LCLS conda environment (`ana-4.0.62-py3`), not the deployer's home.

### 2. `tools/lcls-catalog/` had wrong group (`gu` instead of `ps-data`)

The lcls-catalog tool directory was cloned/copied from a personal workspace and retained the deployer's default group `gu`. Key problems:
- `scripts/` directory was `drwx------` (owner-only) — completely blocked
- Several files were `rw-------` (owner-only)
- The `.uv-cache/` directory also had group `gu`

### 3. `data/lcls-catalog/lcls_parquet/` had wrong group (`gu` instead of `ps-data`)

The parquet data directory (5.9 GB) was rsynced from a personal project directory and inherited group `gu`. Users could only access files through "other" read permissions, which is fragile and unintentional.

## Fixes Applied

### Installed shared Python interpreters

Created `/sdf/group/lcls/ds/dm/apps/dev/python/` with uv-managed Python 3.14 and 3.11:

```bash
mkdir -p /sdf/group/lcls/ds/dm/apps/dev/python

UV_PYTHON_INSTALL_DIR=/sdf/group/lcls/ds/dm/apps/dev/python \
  uv python install 3.14

UV_PYTHON_INSTALL_DIR=/sdf/group/lcls/ds/dm/apps/dev/python \
  uv python install 3.11

chgrp -R ps-data /sdf/group/lcls/ds/dm/apps/dev/python
chmod -R g+rX /sdf/group/lcls/ds/dm/apps/dev/python
```

### Fixed lcls-catalog group ownership

```bash
chgrp -R ps-data /sdf/group/lcls/ds/dm/apps/dev/tools/lcls-catalog
chmod -R g+rX /sdf/group/lcls/ds/dm/apps/dev/tools/lcls-catalog
find /sdf/group/lcls/ds/dm/apps/dev/tools/lcls-catalog -type d -exec chmod g+s {} +

chgrp -R ps-data /sdf/group/lcls/ds/dm/apps/dev/data/lcls-catalog/lcls_parquet
chmod -R g+rX /sdf/group/lcls/ds/dm/apps/dev/data/lcls-catalog/lcls_parquet
find /sdf/group/lcls/ds/dm/apps/dev/data/lcls-catalog/lcls_parquet -type d -exec chmod g+s {} +
```

### Recreated all 4 broken venvs

For each affected tool, deleted and recreated the venv using the shared Python:

```bash
cd /sdf/group/lcls/ds/dm/apps/dev/tools/<tool>
rm -rf .venv
UV_PYTHON_INSTALL_DIR=/sdf/group/lcls/ds/dm/apps/dev/python \
  uv venv --python 3.14   # or 3.11 for confluence-doc
UV_PYTHON_INSTALL_DIR=/sdf/group/lcls/ds/dm/apps/dev/python \
  uv sync                  # or "uv pip install -r requirements.txt" for smartsheet
chgrp -R ps-data .venv
chmod -R g+rX .venv
```

### Updated all env.sh files

Added `UV_PYTHON_INSTALL_DIR` to each tool's `env.sh` so future `uv` operations use the shared Python:

```bash
export UV_PYTHON_INSTALL_DIR="/sdf/group/lcls/ds/dm/apps/dev/python"
```

Updated in: `lcls-catalog`, `tree-sitter-db`, `smartsheet`, `confluence-doc`, `elog-copilot`.

## Lessons and Deployment Checklist

These are the key takeaways to prevent this class of issue in the future.

### Why this happened

The shared deployment at `/sdf/group/lcls/ds/dm/apps/dev/` is built by copying files from personal workspaces. Two things go wrong silently:

1. **`uv` stores Python in `~/.local/share/uv/python/` by default.** When you run `uv venv` or `uv sync` in a shared directory, the resulting `.venv/bin/python` symlink points into your home directory. This works for you but breaks for everyone else.

2. **Files copied from personal directories inherit the personal group.** If your default group is `gu` (not `ps-data`), then `git clone`, `rsync`, `cp`, etc. will create files with group `gu`. The SGID bit on shared directories helps, but only if it was set before the copy.

### Checklist: After copying/creating anything in the shared deployment

1. **Set `UV_PYTHON_INSTALL_DIR` before any `uv` operation:**
   ```bash
   export UV_PYTHON_INSTALL_DIR="/sdf/group/lcls/ds/dm/apps/dev/python"
   ```

2. **After `rsync`, `cp`, `git clone`, or `uv sync`, fix group ownership:**
   ```bash
   chgrp -R ps-data <new-directory>
   chmod -R g+rX <new-directory>
   find <new-directory> -type d -exec chmod g+s {} +
   ```

3. **Verify venv Python symlinks don't point to personal home dirs:**
   ```bash
   readlink /sdf/group/lcls/ds/dm/apps/dev/tools/*/.venv/bin/python
   # Should show /sdf/group/lcls/ds/dm/apps/dev/python/... not /sdf/home/...
   ```

4. **Spot-check group ownership across the deployment:**
   ```bash
   # Should all show ps-data
   ls -ld /sdf/group/lcls/ds/dm/apps/dev/tools/*/
   ls -ld /sdf/group/lcls/ds/dm/apps/dev/data/*/
   ```

5. **Test as a skill invocation**, not just a direct command. The agent skill sources `env.sh` and runs `uv run --project`, which exercises the full path including venv access.

### Follow-up fix: UV_CACHE_DIR and `--frozen` (same day)

After the initial fix, users still got errors like:
```
error: failed to open file `.uv-cache/sdists-v9/.git`: Permission denied (os error 13)
```

**Cause:** Each `env.sh` hardcoded `UV_CACHE_DIR` to the tool's shared `.uv-cache/` directory. `uv` needs write access to its cache (for downloads, locking, etc.), so multiple users can't share one cache directory.

Additionally, `uv run --project` tries to sync the `.venv` before running, which also requires write access.

**Fix applied:**
1. Changed `UV_CACHE_DIR` in all env.sh files to default to `/tmp/uv-cache-$USER` (per-user, writable). Uses `${UV_CACHE_DIR:-/tmp/uv-cache-$USER}` so `env.local` can override for cron jobs.
2. Added `--frozen` flag to all `uv run` calls in `lcat()` and `tsdb()` wrapper functions. This tells `uv` to use the pre-built venv as-is without attempting to sync/write.

**Lesson:** In a shared deployment, `uv` needs two things to be per-user or read-only:
- `UV_CACHE_DIR` — must be writable by the user running `uv` (use `/tmp/uv-cache-$USER`)
- `.venv` — use `--frozen` so `uv run` doesn't try to modify the shared venv

### Checklist: When adding a new tool to the deployment

1. Source the tool's `env.sh` (which sets `UV_PYTHON_INSTALL_DIR`) before running any `uv` commands.
2. If the tool needs a Python version not yet installed in `dev/python/`, install it:
   ```bash
   UV_PYTHON_INSTALL_DIR=/sdf/group/lcls/ds/dm/apps/dev/python uv python install 3.XX
   chgrp -R ps-data /sdf/group/lcls/ds/dm/apps/dev/python
   chmod -R g+rX /sdf/group/lcls/ds/dm/apps/dev/python
   ```
3. After creating the venv and syncing: `chgrp -R ps-data .venv && chmod -R g+rX .venv`
4. Add these exports to the new tool's `env.sh`:
   - `UV_PYTHON_INSTALL_DIR="/sdf/group/lcls/ds/dm/apps/dev/python"`
   - `UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache-$USER}"`
5. If the tool has a wrapper function that calls `uv run`, add the `--frozen` flag.
6. Run the verification commands above.
