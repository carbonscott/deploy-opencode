## Overview

I'm trying to define agents inside opencode.

A few projects that I'm interested in:
- lcls-catalog (lcat)
- daq-logs
- elog-copilot
- confluence-doc
- smartsheet

Some tools require building a database to function at runtime.  For instance,
lcat requires querying many parquet files that require regular updates.  So does daq-log.  Elog-Copilot itself is a project about pulling data to form a database.


```bash
export APP_ROOT="/sdf/group/lcls/ds/dm/apps"
export APP_DATA="$APP_ROOT/dev/data"
export APP_TOOL="$APP_ROOT/dev/tools"
```

### Python Environment

```
export UV_CACHE_DIR=/sdf/group/lcls/ds/dm/apps/dev/env/.UV_CACHE
```

## Applications

### `lcls-catalog`

#### Source Path

Tool path: `/sdf/scratch/users/c/cwang31/proj-lcls-catalog/`
Data path: `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/lcls_parquet/`

#### Deployed Path

Tool path: `$APP_TOOL/lcls-catalog`
Data path: `$APP_DATA/lcls-catalog/lcls_parquet`

### `daq-logs`

#### Source Path

Tool path: `git@github.com:carbonscott/lcls-daq-browser-indexing-scripts.git`
Local clone: `/sdf/scratch/users/c/cwang31/lcls-daq-browser-indexing-scripts/`
Data path: `/sdf/data/lcls/ds/prj/prjdat21/results/appdata/daq_logs.db`

#### Deployed Path

Tool path: `$APP_TOOL/daq-logs`
Data path: `$APP_DATA/daq-logs/daq_logs.db`

### `elog-copilot`

#### Source Path

Tool path: `/sdf/data/lcls/ds/prj/prjcwang31/results/fetch-elog/` (git: `git@github.com:carbonscott/elogfetch.git`)
Data path: `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-skills/elog_*.db` (development snapshots)

#### Deployed Path

Tool path: `$APP_TOOL/elog-copilot`
Data path: `$APP_DATA/elog-copilot/elog-copilot.db` (symlink to latest timestamped DB)
Cron: Every 6 hours on sdfcron001 (`scripts/elog-cron.sh`)

### `confluence-doc`

#### Source Path

Tool path: `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm`
Data path: `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/lcls-docs.db`

#### Deployed Path

Tool path: `$APP_TOOL/confluence-doc`
Data path: `$APP_DATA/confluence-doc/lcls-docs.db`
Cron: Every hour on sdfcron001 (`scripts/confluence-cron.sh`)

### `smartsheet`

#### Source Path

Tool path: `git@github.com:carbonscott/smartsheet-db-scripts.git`
Local clone (deprecated): `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-smartsheet/`

#### Deployed Path

Tool path: `$APP_TOOL/smartsheet`
Data path: `$APP_DATA/smartsheet/closeout_notes.db`
