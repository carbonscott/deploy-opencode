# OpenCode Centralized Deployment

## Directory Layout

```
/sdf/group/lcls/ds/dm/apps/
├── etc/
│   └── key.dat                         # API key (managed by IT)
└── dev/
    ├── opencode/                       # OpenCode shared config (OPENCODE_CONFIG_DIR)
    │   ├── opencode.json               # Provider, models, theme
    │   ├── agents/
    │   │   ├── elog-copilot.md
    │   │   ├── daq-logs.md
    │   │   └── confluence-doc.md
    │   └── skills/
    │       └── lcls-catalog/
    │           └── SKILL.md
    ├── data/                           # Shared data assets
    │   ├── lcls-docs.db                # Confluence documentation DB (2.7M)
    │   ├── daq_logs.db                 # DAQ error logs DB (2.2G)
    │   └── lcls_parquet/               # Catalog parquet files (5.9G)
    └── tools/
        └── lcls-catalog/               # Catalog tool (uv project)
            ├── env.sh                  # Environment setup
            ├── pyproject.toml
            ├── src/
            └── ...
```

## Directory Roles

| Directory | Write Access | Contents |
|-----------|-------------|----------|
| `/sdf/group/lcls/ds/dm/apps/etc/` | IT only | API key (`key.dat`) |
| `/sdf/group/lcls/ds/dm/apps/dev/opencode/` | You | Config, agents, skills |
| `/sdf/group/lcls/ds/dm/apps/dev/data/` | You | Database files, parquet data |
| `/sdf/group/lcls/ds/dm/apps/dev/tools/` | You | Tools that generate/update data |

All employees have **read** access to both `/apps/etc/` and `/apps/dev/`.

## Mechanism

OpenCode scans `OPENCODE_CONFIG_DIR` for `opencode.json`, `agents/`, `skills/`, etc. — in addition to any personal `~/.config/opencode/`.

## Employee Onboarding

Each employee adds one line to their shell profile (`.bashrc` / `.bash_profile`):

```bash
export OPENCODE_CONFIG_DIR=/sdf/group/lcls/ds/dm/apps/dev/opencode
```

No other per-user setup is required.

## IT Action Required

Ask IT to place the shared API key at:

```
/sdf/group/lcls/ds/dm/apps/etc/key.dat
```

The shared `opencode.json` references this path via `{file:/sdf/group/lcls/ds/dm/apps/etc/key.dat}`.

## Updating Data

The database files and parquet data are periodically updated. To refresh:

```bash
# Confluence docs DB
cp /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/lcls-docs.db \
   /sdf/group/lcls/ds/dm/apps/dev/data/

# DAQ logs DB
cp /sdf/data/lcls/ds/prj/prjdat21/results/appdata/daq_logs.db \
   /sdf/group/lcls/ds/dm/apps/dev/data/

# Parquet catalog data
rsync -a --exclude='.uv-cache' \
   /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/lcls_parquet/ \
   /sdf/group/lcls/ds/dm/apps/dev/data/lcls_parquet/
```

## Notes

- **Config precedence** (lowest to highest): global user config < `OPENCODE_CONFIG_DIR` < project config < `OPENCODE_CONFIG_CONTENT`
- **Deep merge**: Users can create `~/.config/opencode/opencode.json` for personal overrides
- **Maintenance**: Edit files in `/apps/dev/opencode/` to update config for all users. Changes take effect on next opencode session.
- **lcls-catalog tool**: Employees can use `source /sdf/group/lcls/ds/dm/apps/dev/tools/lcls-catalog/env.sh` to get the `lcat` command. The env.sh requires `uv` in `$HOME/.local/bin`.
