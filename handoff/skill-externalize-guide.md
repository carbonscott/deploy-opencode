# Skill externalization guide

How to maintain the 15 knowledge-wrapper skills now that they live in per-skill `skill-*` GitHub repos under `carbonscott/`. `deploy-opencode` no longer holds skill content — it holds the **manifest** (`skills.manifest.json`) and the **meta-deploy script** (`deploy.sh`) that walks the manifest.

For audit/history, see `handoff/skill-audit-2026-05-13.md` and `handoff/handoff-externalize-skills-2026-05-13.md`.

## Repo layout (per skill)

Each `skill-<name>` repo has this structure:

```
skill-<name>/
├── README.md                       # one-paragraph: what the skill does + link back to deploy-opencode
├── claude/skills/<name>/           # for users running Claude Code locally
│   └── SKILL.md
│   └── (scripts, references, bin, env.sh, setup.sh as needed)
├── opencode/skills/<name>/         # deployed to /sdf/group/lcls/ds/dm/apps/dev/opencode/skills/<name>/
│   └── SKILL.md                    # content identical to claude/ side
│   └── (mirror of claude/skills/<name>/ contents)
└── tools/<some-dir>/               # optional — cron sync scripts (e.g. tools/epics-docs/scripts/epics-docs-cron.sh)
```

Conventions:
- `claude/skills/<name>/` and `opencode/skills/<name>/` hold **identical content, duplicated**. No `shared/` directory. (User explicitly chose duplication over a shared root.)
- `tools/<X>/` exists only for skills that have a data-sync cron job. It rsyncs to `/sdf/group/lcls/ds/dm/apps/dev/tools/<X>/`.
- The skill does **not** contain bulk data. Data lives centrally at `/sdf/group/lcls/ds/dm/apps/dev/data/<X>/` (e.g. `epics-docs/`, `sdf-docs/`) and is managed by cron.
- No per-repo `install.sh`. Deployment is centralized in this repo's `deploy.sh`.
- Free-form scripts inside each repo (no shared installer library).

## Manifest

`skills.manifest.json` at the root of `deploy-opencode` lists every externalized skill:

```json
{
  "skills": [
    {
      "name": "cuda-docs",
      "repo": "carbonscott/skill-cuda-docs",
      "ref": "main",
      "cron": null,
      "central_data": "/sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs"
    },
    {
      "name": "ask-epics",
      "repo": "carbonscott/skill-ask-epics",
      "ref": "main",
      "cron": {
        "schedule": "0 3 * * 0",
        "script": "tools/epics-docs/scripts/epics-docs-cron.sh",
        "host": "sdfcron001"
      },
      "central_data": "/sdf/group/lcls/ds/dm/apps/dev/data/epics-docs"
    }
  ]
}
```

JSON was chosen over YAML because the deploy host's system Python (3.6) has no `yaml`, but `jq` is available globally. `deploy.sh` parses with `jq`.

Fields:
- `name` — directory name under `opencode/skills/` (no `skill-` prefix).
- `repo` — `<owner>/skill-<name>` on GitHub.
- `ref` — branch name (recommended). Tags work but `deploy.sh` will not auto-reset to them on re-deploy (the cached `--depth=1` clone sticks until you wipe `$STAGING_ROOT/<name>`). Commit SHAs are **not supported** in v1 — `git clone --depth=1 -b <sha>` rejects them.
- `cron` — `null` for skills with no data sync. Otherwise: `schedule` (crontab format), `script` (path inside the repo), `host` (cron host, typically `sdfcron001`).
- `central_data` — absolute path of the central data dir the skill operates on, or `null`. **Advisory only** — `deploy.sh` does not read or enforce this field. It exists to remind operators which central dir each skill expects.

## Permissions (the recurring gotcha)

Every deployed file under `/sdf/group/lcls/ds/dm/apps/dev/` must be readable by the `ps-data` group:

```bash
chgrp -R ps-data <path>
chmod -R g+rX <path>
```

See `docs/incident-permissions-fix-2026-02-12.md` for the original incident. `deploy.sh` enforces this after every rsync — if you change the script, do not drop these calls.

## How `deploy.sh` works

1. Read `skills.manifest.json` (parsed with `jq`).
2. For each skill:
   a. Clone or fetch `git@github.com:<repo>.git` at `<ref>` into `$STAGING_ROOT/<name>`.
   b. `rsync -a --delete <stage>/opencode/skills/<name>/` → `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/<name>/`.
   c. Fix permissions (chgrp ps-data + g+rX).
   d. Ensure `opencode/agents/<name>` symlink → `../skills/<name>` exists in the deployed `agents/` dir.
   e. If `<stage>/tools/` exists, rsync each `tools/<X>/` to `/sdf/group/lcls/ds/dm/apps/dev/tools/<X>/` and fix perms.
3. Cron installation is **out of scope** for `deploy.sh` v1 — operator installs/updates `crontab` on `sdfcron001` manually using the `schedule + script` info from the manifest. Future versions may automate this.

Dry-run with `DRY_RUN=1 ./deploy.sh`. Filter to one skill with `./deploy.sh <name>`.

## Adding a new skill

1. Create the repo on GitHub manually: `gh repo create carbonscott/skill-<name> --public`. Use `--public` for skills with no LCLS-internal data tie-ins (all current 15 are public); use `--private` if the skill references internal hostnames, credentials, or non-public data sources.
2. Populate locally with the layout above.
3. Push `main`.
4. Add a manifest entry to `skills.manifest.json`.
5. Run `./deploy.sh <name>` once to populate the deployed copy.
6. If cron is needed, install the crontab entry on `sdfcron001` matching the manifest.

## Removing/renaming a skill

- To stop deploying: delete the manifest entry. `deploy.sh` does **not** purge stale deployed dirs — remove `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/<name>/` manually.
- To rename: rename the GitHub repo (`gh repo rename`), update the `name`/`repo` fields in the manifest, rename the deployed dir, then re-run `deploy.sh`.

## Known gaps in the reference (cuda-docs)

The first reference skill, `cuda-docs`, exercises:
- ✅ `claude/+opencode/` layout
- ✅ Manifest entry with `cron: null`
- ✅ `deploy.sh` rsync + permissions

But does **not** exercise:
- ❌ `tools/` dir / cron rsync
- ❌ `env.sh` / `setup.sh` runtime helpers
- ❌ `bin/` dir
- ❌ Re-using an existing remote (cuda-docs has no prior remote)
- ❌ Renamed remote (ask-slac-ai-tools, xpm-seq)

**Obligation**: after the first cron-bearing skill (likely `ask-epics`) is extracted in Phase 5, revise this doc with a "cron-bearing reference" section. Ralph stories for cron skills can then point at that reference instead of guessing.

## Centrally-managed skills (untouched by this effort)

These are **not** in the manifest and stay in `deploy-opencode` proper. They have ongoing data-service tie-ins or sit on top of LCLS-internal repos that the deploy-opencode maintainer controls directly:

- `lcls-catalog`
- `confluence-doc`, `elog-copilot`, `daq-logs`, `smartsheet` (data-service agents, not skills)
- `nano-isaac`, `find-rings` (LCLS-coupled tools)

Revisit later if the pattern proves out for wrappers.
