# OpenCode Centralized Deployment

This project manages the shared opencode deployment for the LCLS team.

## Deployed Directory Structure

All shared files live under `/sdf/group/lcls/ds/dm/apps/`:

| Path | Owner | Purpose |
|------|-------|---------|
| `etc/key.dat` | IT | API key (read-only for employees) |
| `dev/bin/uv` | You | Shared uv binary (for lcls-catalog, tree-sitter-db, etc.) |
| `dev/bin/docs-index` | You | Shared docs-index script (FTS5 indexer for doc collections) |
| `dev/python/` | You | Shared uv-managed Python installs (3.14, 3.11); venvs symlink here instead of per-user `~/.local/share/uv/python/` |
| `dev/opencode/opencode.json` | You | Shared config (provider, models) |
| `dev/opencode/agents/*.md` | You | Agent definitions |
| `dev/opencode/commands/*.md` | You | Slash commands (approval, clarify, taskify) |
| `dev/opencode/skills/lcls-catalog/` | You | lcls-catalog skill |
| `dev/opencode/skills/askcode/` | You | askcode skill (code indexing) |
| `dev/opencode/skills/ask-lcls2/` | You | ask-lcls2 skill (lcls2/psana2 codebase) |
| `dev/opencode/skills/ask-smalldata/` | You | ask-smalldata skill (smalldata_tools codebase) |
| `dev/opencode/skills/cuda-docs/` | You | cuda-docs skill (CUDA documentation search) |
| `dev/opencode/skills/ask-slurm-s3df/` | You | ask-slurm-s3df skill (S3DF Slurm cluster assistant) |
| `dev/opencode/skills/nano-isaac/` | You | nano-isaac skill (AI catalysis research assistant for AP-XPS) |
| `dev/opencode/skills/docs-search/` | You | docs-search skill (documentation search strategy using docs-index) |
| `dev/opencode/skills/ask-s3df/` | You | ask-s3df skill (S3DF documentation assistant) |
| `dev/opencode/skills/find-rings/` | You | find-rings skill (diffraction ring detection for detector calibration) |
| `dev/opencode/skills/experimental-hutch-python/` | You | experimental-hutch-python skill [EXPERIMENTAL] (beamline control assistant + IPython bridge) |
| `dev/opencode/skills/ask-olcf/` | You | ask-olcf skill (OLCF documentation assistant) |
| `dev/data/sdf-docs/` | You | sdf-docs git repo with FTS5 search index (from slaclab/sdf-docs, branch: prod) |
| `dev/tools/sdf-docs/` | You | sdf-docs sync scripts (daily git pull + re-index) |
| `dev/data/olcf-docs/` | You | olcf-user-docs git repo with FTS5 search index (from olcf/olcf-user-docs) |
| `dev/tools/olcf-docs/` | You | olcf-docs sync scripts (weekly git pull + re-index) |
| `dev/data/cuda-docs/` | You | CUDA documentation markdown files (Best Practices, Runtime API, Driver API) |
| `dev/data/nano-isaac/` | You | nanoISAAC data files (JSON databases, Python scripts, experimental data) |
| `dev/software/lcls2/` | You | lcls2 git repo with .agent_docs and .code-index.db |
| `dev/software/smalldata_tools/` | You | smalldata_tools git repo with .agent_docs and .code-index.db |
| `dev/data/confluence-doc/lcls-docs.db` | You | Confluence docs SQLite DB |
| `dev/data/daq-logs/daq_logs.db` | You | DAQ error logs SQLite DB |
| `dev/data/lcls-catalog/lcls_parquet/` | You | Catalog parquet files |
| `dev/data/elog-copilot/elog-copilot.db` | You | Elog experiment SQLite DB (~1.3G, symlink to latest) |
| `dev/data/smartsheet/closeout_notes.db` | You | Smartsheet experiment closeout SQLite DB |
| `dev/tools/confluence-doc/` | You | Confluence export pipeline (git repo) |
| `dev/tools/lcls-catalog/` | You | lcls-catalog uv project |
| `dev/tools/daq-logs/` | You | DAQ log sync scripts (git clone) |
| `dev/tools/elog-copilot/` | You | elogfetch uv project (**pinned at v1.0.0-stable, detached HEAD — do NOT git pull**) |
| `dev/tools/smartsheet/` | You | Smartsheet closeout sync scripts (git clone) |
| `dev/tools/nano-isaac/` | You | nano-isaac uv project (DTCS runtime for XPS simulations) |
| `dev/tools/find-rings/` | You | find-rings uv project (numpy + Pillow for ring detection) |
| `dev/tools/tree-sitter-db/` | You | Code indexing tool (uv project) |

Employees set `OPENCODE_CONFIG_DIR=/sdf/group/lcls/ds/dm/apps/dev/opencode` to use this.

## Source → Deploy Mapping

Deployed files are copies (not symlinks) from these source projects:

| Deployed file | Source |
|---------------|--------|
| `agents/elog-copilot.md` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-skills/.opencode/agents/elog-copilot.md` |
| `agents/daq-logs.md` | `/sdf/data/lcls/ds/prj/prjcwang31/results/proj-debug-daq/.opencode/agents/daq-logs.md` |
| `agents/confluence-doc.md` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/.opencode/agents/confluence-doc.md` |
| `skills/lcls-catalog/` | `/sdf/scratch/users/c/cwang31/proj-lcls-catalog/.opencode/skills/lcls-catalog/` |
| `data/confluence-doc/lcls-docs.db` | Cron job via `tools/confluence-doc/scripts/confluence-cron.sh` (every hour on sdfcron001) |
| `tools/confluence-doc/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/` (minimal file set, git repo) |
| `data/daq-logs/daq_logs.db` | Cron job via `tools/daq-logs/scripts/run_daq_log_sync.sh` (every 5 min on sdfcron001) |
| `tools/daq-logs/` | `git@github.com:carbonscott/lcls-daq-browser-indexing-scripts.git` |
| `data/lcls-catalog/lcls_parquet/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/lcls_parquet/` |
| `tools/lcls-catalog/` | `/sdf/scratch/users/c/cwang31/proj-lcls-catalog/` |
| `tools/elog-copilot/` | `/sdf/data/lcls/ds/prj/prjcwang31/results/fetch-elog/` |
| `data/elog-copilot/elog-copilot.db` | Generated by elogfetch cron job (every 6h on sdfcron001) |
| `agents/smartsheet.md` | Authored directly in deployed copy |
| `tools/smartsheet/` | `git@github.com:carbonscott/smartsheet-db-scripts.git` |
| `data/smartsheet/closeout_notes.db` | Cron job via `tools/smartsheet/scripts/smartsheet-cron.sh` (daily on sdfcron001) |
| `skills/askcode/` | Authored directly in deployed copy |
| `tools/tree-sitter-db/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/fun/play-tree-sitter/tree-sitter-db/` |
| `software/lcls2/` | `git@github.com:slac-lcls/lcls2.git` (full clone) |
| `software/lcls2/.agent_docs/` | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/lcls2/.agent_docs/` |
| `software/lcls2/.code-index.db` | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/lcls2/.code-index.db` |
| `software/smalldata_tools/` | `git@github.com:slac-lcls/smalldata_tools.git` (full clone) |
| `software/smalldata_tools/.agent_docs/` | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/smalldata_tools/.agent_docs/` |
| `software/smalldata_tools/.code-index.db` | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/smalldata_tools/.code-index.db` |
| `skills/ask-lcls2/` | Authored directly in deployed copy |
| `skills/ask-smalldata/` | Authored directly in deployed copy |
| `skills/cuda-docs/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/cuda-docs/` |
| `data/cuda-docs/*.md` | Static markdown files (no cron job needed) |
| `skills/ask-slurm-s3df/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-slurm-s3df/` |
| `skills/docs-search/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/docs-search/` |
| `bin/docs-index` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/docs-search/scripts/docs-index` |
| `skills/ask-s3df/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-s3df/` |
| `data/sdf-docs/` | `https://github.com/slaclab/sdf-docs.git` (branch: prod); cron via `tools/sdf-docs/scripts/sdf-docs-cron.sh` (daily) |
| `tools/sdf-docs/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-s3df/tools/` |
| `commands/*.md` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/opencode/commands/` |
| `skills/nano-isaac/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/nano-isaac/` (skill + sub-skills + references) |
| `data/nano-isaac/` | nanoISAAC repo data files (copied by `deploy-nano-isaac.sh`) |
| `tools/nano-isaac/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/nano-isaac/tool/` (env.sh + pyproject.toml) |
| `skills/find-rings/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/find-rings/` (skill + references + scripts) |
| `tools/find-rings/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/find-rings/tool/` (env.sh + pyproject.toml) |
| `skills/experimental-hutch-python/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/experimental-hutch-python/` (skill + references + scripts) |
| `skills/ask-olcf/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-olcf/` |
| `data/olcf-docs/` | `https://github.com/olcf/olcf-user-docs.git`; cron via `tools/olcf-docs/scripts/olcf-docs-cron.sh` (weekly) |
| `tools/olcf-docs/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-olcf/tools/` |

When copying agents/skills, hardcoded paths must be updated to the shared locations.

## Updating Deployed Data

```bash
# Confluence docs DB — managed by cron (every hour via tools/confluence-doc/scripts/confluence-cron.sh)
# No manual copy needed. To check status:
#   /sdf/group/lcls/ds/dm/apps/dev/tools/confluence-doc/scripts/confluence-cron.sh status

# DAQ logs DB — managed by cron (every 5 min via tools/daq-logs/scripts/sync-cron.sh)
# No manual copy needed. To check status:
#   /sdf/group/lcls/ds/dm/apps/dev/tools/daq-logs/scripts/sync-cron.sh status

# Parquet catalog data (5.9G)
rsync -a --exclude='.uv-cache' \
   /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/lcls_parquet/ \
   /sdf/group/lcls/ds/dm/apps/dev/data/lcls-catalog/lcls_parquet/

# Smartsheet closeout DB — managed by cron (daily via tools/smartsheet/scripts/smartsheet-cron.sh)
# No manual copy needed. To check status:
#   tail /sdf/group/lcls/ds/dm/apps/dev/data/smartsheet/cron.log

# sdf-docs — managed by cron (daily via tools/sdf-docs/scripts/sdf-docs-cron.sh)
# No manual copy needed. To check status:
#   tail /sdf/group/lcls/ds/dm/apps/dev/data/sdf-docs/cron.log

# olcf-docs — managed by cron (weekly via tools/olcf-docs/scripts/olcf-docs-cron.sh)
# No manual copy needed. To check status:
#   tail /sdf/group/lcls/ds/dm/apps/dev/data/olcf-docs/cron.log
```

## Key Config Details

- `opencode.json` references the API key via `{file:/sdf/group/lcls/ds/dm/apps/etc/key.dat}`
- Config precedence: global user < OPENCODE_CONFIG_DIR < project < OPENCODE_CONFIG_CONTENT
- The `tools/lcls-catalog/env.sh` defines the `lcat` shell function and sets `LCLS_CATALOG_APP_DIR` and `CATALOG_DATA_DIR`
- The `tools/daq-logs/scripts/env.sh` sets `DAQ_LOGS_APP_DIR` and `DAQ_LOGS_DATA_DIR`; cron job runs every 5 min syncing DAQ logs to `data/daq-logs/`
- The `tools/elog-copilot/env.sh` defines `ELOG_COPILOT_APP_DIR` and `ELOG_COPILOT_DATA_DIR`; cron job runs every 6 hours updating `data/elog-copilot/elog-copilot.db`
- The `tools/confluence-doc/env.sh` defines `CONFLUENCE_DOC_APP_DIR` and `CONFLUENCE_DOC_DATA_DIR`; cron job runs every hour exporting Confluence docs to `data/confluence-doc/lcls-docs.db`
- The `tools/smartsheet/env.sh` defines `SMARTSHEET_APP_DIR` and `SMARTSHEET_DATA_DIR`; reads API key from `dev/env/smartsheet.dat`; cron job runs daily syncing closeout data to `data/smartsheet/`
- The `tools/tree-sitter-db/env.sh` defines `TREE_SITTER_DB_APP_DIR` and `TREE_SITTER_DB_DATA_DIR`; provides `tsdb` wrapper for on-demand code indexing (no cron job)
- The `tools/nano-isaac/env.sh` defines `NANO_ISAAC_APP_DIR` and `NANO_ISAAC_DATA_DIR`; provides `nano_isaac_run` wrapper for DTCS runtime (no cron job)
- The `tools/find-rings/env.sh` defines `FIND_RINGS_APP_DIR`; provides `find_rings_run` wrapper for ring detection (no cron job)
- The `tools/sdf-docs/env.sh` defines `SDF_DOCS_APP_DIR` and `SDF_DOCS_DATA_DIR`; cron job runs daily syncing sdf-docs repo and rebuilding FTS5 search index
- The `tools/olcf-docs/env.sh` defines `OLCF_DOCS_APP_DIR` and `OLCF_DOCS_DATA_DIR`; cron job runs weekly syncing olcf-user-docs repo and rebuilding FTS5 search index
- **Skills need symlinks in agents/ for @invocation**: Opencode loads from `agents/` directory. Skills in `skills/` need symlinks in `agents/` to be invoked with `@skill-name`. Current symlinks: `agents/askcode -> ../skills/askcode`, `agents/lcls-catalog -> ../skills/lcls-catalog`, `agents/ask-lcls2 -> ../skills/ask-lcls2`, `agents/ask-smalldata -> ../skills/ask-smalldata`, `agents/cuda-docs -> ../skills/cuda-docs`, `agents/ask-slurm-s3df -> ../skills/ask-slurm-s3df`, `agents/nano-isaac -> ../skills/nano-isaac`, `agents/docs-search -> ../skills/docs-search`, `agents/ask-s3df -> ../skills/ask-s3df`, `agents/find-rings -> ../skills/find-rings`, `agents/experimental-hutch-python -> ../skills/experimental-hutch-python`, `agents/ask-olcf -> ../skills/ask-olcf`
- The `software/update-index.sh` script updates git repos and regenerates code indexes: `./update-index.sh [lcls2|smalldata_tools|all]`

## uv for Shared Deployment

The shared tools use `uv` to manage Python projects. Three settings are critical for multi-user access:

1. **`UV_PYTHON_INSTALL_DIR="/sdf/group/lcls/ds/dm/apps/dev/python"`** — Python interpreters must live in a shared location, not `~/.local/share/uv/python/` (which is owner-only). Each env.sh exports this. When adding a new Python version:
   ```bash
   UV_PYTHON_INSTALL_DIR=/sdf/group/lcls/ds/dm/apps/dev/python uv python install 3.XX
   chgrp -R ps-data /sdf/group/lcls/ds/dm/apps/dev/python && chmod -R g+rX /sdf/group/lcls/ds/dm/apps/dev/python
   ```

2. **`UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache-$USER}"`** — `uv` needs write access to its cache. Each user gets their own cache in `/tmp/`. Cron jobs can override via `env.local`.

3. **`uv run --frozen`** — Wrapper functions (`lcat`, `tsdb`) use `--frozen` so `uv run` doesn't try to sync/write to the shared `.venv`. The venv is pre-built by the maintainer; users only read from it.

After creating or updating a venv, fix permissions:
```bash
chgrp -R ps-data .venv && chmod -R g+rX .venv
```

See `docs/incident-permissions-fix-2026-02-12.md` for full context on these requirements.

## Agent/Skill Config Locations

When modifying an agent or skill, update all copies. Changes in the source are for local development; changes in the deployed copy take effect for all employees.

### lcls-catalog

| Copy | Path |
|------|------|
| Deployed (opencode) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/lcls-catalog/SKILL.md` |
| Source (opencode) | `/sdf/scratch/users/c/cwang31/proj-lcls-catalog/.opencode/skills/lcls-catalog/SKILL.md` |
| Source (claude) | `/sdf/scratch/users/c/cwang31/proj-lcls-catalog/.claude/skills/lcls-catalog/SKILL.md` |

### confluence-doc

| Copy | Path |
|------|------|
| Deployed (opencode agent) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/agents/confluence-doc.md` |
| Source (opencode agent) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/.opencode/agents/confluence-doc.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/.claude/skills/confluence-doc/SKILL.md` |

### elog-copilot

| Copy | Path |
|------|------|
| Deployed (opencode agent) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/agents/elog-copilot.md` |
| Source (opencode agent) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-skills/.opencode/agents/elog-copilot.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-skills/.claude/skills/elog-copilot/SKILL.md` |

**Deployed tools frozen (2026-02-25):** The deployed `tools/elog-copilot/` directory is pinned at tag `v1.0.0-stable` (commit `4dc1759`) with detached HEAD to prevent accidental `git pull`. The elogfetch repo has 12+ open PRs for a major refactor (async, SQLAlchemy/Alembic, gssapi). Review and merge PRs on GitHub or in the source dir — never git pull in the deployed dir. Upgrade procedure:
1. Disable cron: `tools/elog-copilot/scripts/elog-cron.sh disable`
2. Update code: `cd tools/elog-copilot && git fetch origin && git checkout v<new-tag> --detach`
3. Rebuild venv: `uv sync && chgrp -R ps-data .venv && chmod -R g+rX .venv`
4. Test: `scripts/elog-cron.sh test`
5. Re-enable cron: `scripts/elog-cron.sh enable`

### smartsheet

| Copy | Path |
|------|------|
| Deployed (opencode agent) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/agents/smartsheet.md` |

### askcode

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/askcode/SKILL.md` |
| Source (tool) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/fun/play-tree-sitter/tree-sitter-db/` |

### ask-lcls2

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-lcls2/SKILL.md` |
| Software repo | `/sdf/group/lcls/ds/dm/apps/dev/software/lcls2/` |
| Agent docs | `/sdf/group/lcls/ds/dm/apps/dev/software/lcls2/.agent_docs/` |
| Code index | `/sdf/group/lcls/ds/dm/apps/dev/software/lcls2/.code-index.db` |
| Agent docs source | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/lcls2/.agent_docs/` |

### ask-smalldata

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-smalldata/SKILL.md` |
| Software repo | `/sdf/group/lcls/ds/dm/apps/dev/software/smalldata_tools/` |
| Agent docs | `/sdf/group/lcls/ds/dm/apps/dev/software/smalldata_tools/.agent_docs/` |
| Code index | `/sdf/group/lcls/ds/dm/apps/dev/software/smalldata_tools/.code-index.db` |
| Agent docs source | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/smalldata_tools/.agent_docs/` |

### cuda-docs

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/cuda-docs/SKILL.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/cuda-docs/SKILL.md` |
| Data files | `/sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs/*.md` |

### ask-slurm-s3df

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-slurm-s3df/SKILL.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-slurm-s3df/SKILL.md` |
| Reference doc | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/docs/s3df-slurm-research.md` |

### nano-isaac

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/nano-isaac/SKILL.md` |
| Source (skill + tool + scripts) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/nano-isaac/` |
| Upstream repo | `git@github.com:ISAAC-DOE/nanoISAAC.git` |
| Data files | `/sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/` |
| Tool env | `/sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/` |

### ask-s3df

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-s3df/SKILL.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-s3df/SKILL.md` |
| Data (git clone) | `/sdf/group/lcls/ds/dm/apps/dev/data/sdf-docs/` |
| Cron tools | `/sdf/group/lcls/ds/dm/apps/dev/tools/sdf-docs/` |
| Cron tools source | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-s3df/tools/` |

### ask-olcf

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-olcf/SKILL.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-olcf/SKILL.md` |
| Data (git clone) | `/sdf/group/lcls/ds/dm/apps/dev/data/olcf-docs/` |
| Cron tools | `/sdf/group/lcls/ds/dm/apps/dev/tools/olcf-docs/` |
| Cron tools source | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-olcf/tools/` |

### docs-search

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/docs-search/SKILL.md` |
| Deployed (script) | `/sdf/group/lcls/ds/dm/apps/dev/bin/docs-index` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/docs-search/SKILL.md` |
| Source (script) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/docs-search/scripts/docs-index` |

### find-rings

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/find-rings/SKILL.md` |
| Source (skill + tool + scripts) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/find-rings/` |
| Tool env | `/sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/` |

### experimental-hutch-python

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/experimental-hutch-python/SKILL.md` |
| Source (skill + scripts) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/experimental-hutch-python/` |
| Prototype | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/fun-stuff/test-hutch-python/` |

### commands (approval, clarify, taskify, clarify-before-research)

| Copy | Path |
|------|------|
| Deployed (opencode commands) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/commands/*.md` |
| Source (opencode commands) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/opencode/commands/*.md` |
| Source (claude commands) | `/sdf/home/c/cwang31/.claude/commands/*.md` (personal Claude Code originals) |
