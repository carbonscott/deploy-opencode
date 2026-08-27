# Manifest-harness change — handoff

**Status:** implemented, rehearsed in `/tmp`, **not committed, not pushed, not deployed.**
**Branch:** `main` @ `860ac10`. **Date:** 2026-08-27.
**Full design + rationale:** `docs/design-manifest-harness.md` — start at its "AS BUILT" section.
Read this before you run `./deploy.sh` against anything real.

---
## 1. What changed and why

**Why.** Skill metadata (the `description` a harness shows, the slug, the kind) used to live
in each of the 17 external repos, duplicated across a `claude/` and an `opencode/` tree —
so changing a description meant a PR per repo. This change moves that metadata into
`skills.manifest.json`, and lets the external repos stay in plain native Claude Code shape
with no `skill.json` and no content change.

**How.** Each manifest entry gains a `harness` block. `deploy.sh` writes it to a temp JSON
file and hands it to `render.sh --meta`, which strips the repo's own YAML frontmatter and
emits exactly one regenerated block per target.

| file | lines | state | change |
|---|---|---|---|
| `skills.manifest.json` | 280 | tracked, MODIFIED | 17/17 entries gained a `harness` block. `jq -S 'del(.skills[].harness)'` diffs **empty** vs `HEAD` — nothing else moved. |
| `deploy.sh` | 572 | tracked, MODIFIED | `has_harness` TSV column; `write_harness_meta()` + cleanup trap; `resolve_harness_source()`; dry-run no longer mkdirs. |
| `render.sh` | 429 | **untracked** | `--meta` flag; `skill.json` demoted to fallback; frontmatter stripping at all 4 call sites. |
| `validate-manifest.sh` | 285 | **untracked** | new; validates the manifest. |
| `docs/design-manifest-harness.md` | 1449 | **untracked** | the spec, corrected to match the code. |

**The one property that makes this safe to ship:** `description_menu` was seeded
**verbatim** from `description_auto` for all 17, so the first deploy should be a
**no-op on description text**. If the rehearsal diff shows description changes, stop —
something is wrong.

---
## 2. Re-run the rehearsal

All of it lands in `/tmp`. Nothing touches `/sdf/group/lcls/ds/dm/apps/`.

```sh
cd /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode

# 0. Validate the manifest first. Must exit 0.
./validate-manifest.sh skills.manifest.json ; echo "exit=$?"

# 1. Refresh the writable staging copy. NEVER rehearse against /tmp/mhr-staging
#    (those are the pristine reference clones).
rm -rf /tmp/mhr-work/staging
mkdir -p /tmp/mhr-work
cp -a /tmp/mhr-staging /tmp/mhr-work/staging

# 2. Mock deploy root.
rm -rf /tmp/mhr-mock-deploy
mkdir -p /tmp/mhr-mock-deploy/opencode/agents /tmp/mhr-mock-deploy/opencode/skills

# 3. Dry run first — must write nothing.
DEPLOY_ROOT=/tmp/mhr-mock-deploy STAGING_ROOT=/tmp/mhr-work/staging \
  DRY_RUN=1 ./deploy.sh

# 4. Real mock deploy. Allow ~15 min for 17 repos.
DEPLOY_ROOT=/tmp/mhr-mock-deploy STAGING_ROOT=/tmp/mhr-work/staging \
  ./deploy.sh 2>&1 | tee /tmp/mhr-work/deploy.log

# 5. Diff the result against the frozen live snapshot.
diff -r /tmp/mhr-live-snapshot/opencode /tmp/mhr-mock-deploy/opencode
```

Reference material already on the host: `/tmp/mhr-staging/<name>` (17 pristine clones,
never deploy against these), `/tmp/mhr-live-snapshot/opencode` (frozen live tree, 3532
files), `/tmp/mhr-recon/live-inventory.tsv` (3828 lines: `relpath TAB type TAB size TAB
md5-or-symlink-target`), `/tmp/mhr-recon/repo-survey.json` (17-repo survey, verbatim
descriptions).

---
## 3. Expected diff noise — confirm each, do not assume

The step-5 diff will **not** be empty. Known and fine:

- **3 extra live skill dirs** — `lcls-catalog`, `smartsheet`, `token-usage` are hand-managed.
  Nothing in this repo governs them; a mock deploy simply will not create them.
- **Unmanaged live files** — `opencode.json` + 5 `.bak` siblings, `node_modules/` (~57 MB),
  `package.json`, `package-lock.json`, `bun.lock`, `.gitignore`, and a hand-maintained
  `commands/` dir of 14 `.md`. `deploy.sh` owns none of it.
- **`agents/`** — live holds 20 symlinks plus 4 regular `.md` files (`confluence-doc.md`,
  `daq-logs.md`, `elog-copilot.md`, `experimental-elog-copilot-postgres.md`, and one `.bak`).
- **`claude/` is brand new** — the live tree has none. The rehearsal creates it for the first time.
- **Permissions/modes** — `/tmp` is not setgid `ps-data`; the mock root is group `gu`.

**The one difference that matters:** the live `SKILL.md` files were rendered by the OLD path
(checked-in `opencode/skills/<name>/`, no frontmatter regeneration). The new path renders from
`claude/skills/<name>/` with stripped-and-regenerated frontmatter. **Whether the opencode-side
`SKILL.md` bodies come out byte-identical is the question the diff exists to answer.** Bodies
should match; only the frontmatter block should differ, and its `description:` should match what
the live file already said.

---
## 4. Before you deploy for real

- [ ] `./validate-manifest.sh` exits `0`.
- [ ] Rehearsal diff reviewed; every difference maps to §3 above. **No unexplained ones.**
- [ ] **No description text changed** for any of the 17 (see §1).
- [ ] Cron hazard handled — see §6. This is the one that can hurt 3687 people.
- [ ] `git add` + commit the four files (a later agent does this; it has not happened yet).
      Name every path explicitly. **Never `git add -A`** — the working tree holds unrelated
      human work (`memory/`, `research-loop/`, apptainer + bedrock docs, `.bak` files, a 43 MB `.sif`).
- [ ] Decide `DEPLOY_CLAUDE`. It defaults to `1`, so the **first real deploy creates
      `$DEPLOY_ROOT/claude/`** via an `ensure_claude_root()` path only ever exercised against a
      fake root. A wrong group or stray `other::r-x` there is the 2026-02-12 incident.
      Consider `DEPLOY_CLAUDE=0` for the first run.

---
## 5. Recommended first live deploy

Do not start with a bare `./deploy.sh`.

```sh
# 1. Dry run against the real root. Writes nothing.
DRY_RUN=1 ./deploy.sh

# 2. One low-traffic skill, opencode only, to prove the pipeline end to end.
DEPLOY_CLAUDE=0 ./deploy.sh cuda-docs
#    Then inspect the deployed SKILL.md by hand and actually invoke the skill.

# 3. The 12 skills that are NOT cron-hazardous (see §6), still opencode-only.
DEPLOY_CLAUDE=0 ./deploy.sh ask-ami askcode ask-lcls2 ask-slac-ai-tools \
  ask-slurm-s3df ask-smalldata confluence-search docs-search elog-search \
  experimental-hutch-python xpm-seq

# 4. The five cron repos — ONLY after §6 is resolved.
# 5. Re-run with DEPLOY_CLAUDE=1 once claude/ root permissions are verified.
```

---
## 6. Cron hazard — READ THIS

**Re-verified 2026-08-27. Still real, five for five.** Pre-existing; this change neither
causes nor cures it. But a deploy triggers it.

`skill-ask-{epics,nersc,s3df,tiled,olcf}` each carry one divergent line. The repo's `main`
says `chgrp -R ps-data`; the live deployed script says `ps-users`:

| repo / clone dir | tools dir | line | repo `main` | live |
|---|---|---|---|---|
| `skill-ask-epics` / `ask-epics` | `epics-docs` | 51 | `ps-data` | `ps-users` |
| `skill-ask-nersc` / `ask-nersc` | `nersc-docs` | 37 | `ps-data` | `ps-users` |
| `skill-ask-s3df` / `ask-s3df` | `sdf-docs` | 38 | `ps-data` | `ps-users` |
| `skill-ask-tiled` / `ask-tiled` | `tiled-docs` | 37 | `ps-data` | `ps-users` |
| `skill-ask-olcf` / `ask-olcf` | `olcf-docs` | 38 | `ps-data` | `ps-users` |

**Impact.** `deploy.sh` rsyncs `tools/` unconditionally, so deploying any of the five reverts
its cron script. The next cron fire re-chgrps that corpus from `ps-users` (**3748** members)
to `ps-data` (**61**) — 3687 people lose read access, per corpus.
**`sdf-docs` is hourly** (`CRON_SCHEDULE="${CRON_SCHEDULE:-0 * * * *}"` on `sdfcron001`), so
first damage lands within the hour. It is not latent.

**Fix — one merge away.** Five branches, one commit each
(`Fix cron chgrp target: ps-data -> ps-users`), at
`/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/iter6-cron-fix/skill-ask-{epics,nersc,s3df,tiled,olcf}`,
branch `fix/cron-chgrp-ps-users`. They are **committed but UNPUSHED**, so a `deploy.sh` that
clones from GitHub cannot see them. Push and merge them to `main` before deploying those five.

**Stopgap until then:** deploy by explicit name, excluding all five (§5 step 3).

**Pre-flight assertion** — for each of the five, this must print `1` before you proceed:

```sh
grep -c 'chgrp -R ps-users' <clone>/tools/<x>-docs/scripts/<x>-docs-cron.sh
```

**Related, still open:** `tiled-docs-cron.sh` and `olcf-docs-cron.sh` are mode `0644` on both
sides, so the tiled cron has never successfully run. `rsync -a` preserves the mode — a deploy
neither fixes nor worsens it.

---
## 7. Open questions

1. **`migrate.sh`'s fate.** Recommendation (design doc §G): mark DEPRECATED now, delete when
   the `deploy-opencode` repo's own `src/<slug>/` migration closes out; do **not** rework it.
   It is the only producer of the `skill.json` shape `render.sh`'s fallback still consumes, and
   deleting a producer while keeping the consumer is the worse error. **Not yet actioned.**
2. **Should `description_menu` be shortened?** All 17 are currently verbatim copies of
   `description_auto` — deliberately, so the first deploy provably changes no description text.
   That means the @-menu shows long paragraphs. Shortening them into real menu labels is a
   per-repo **human editorial decision**, not something to automate. `validate-manifest.sh`
   already `WARN`s on every menu string over 120 chars, so the backlog is self-listing (17 today).
3. **Skill invocation has never been tested end to end.** Every proof so far is about bytes on
   disk — rendered files, diffs, checksums. Nobody has loaded a deployed skill in Claude Code or
   opencode and run it. Do this at §5 step 2, on one skill, before going wide.
4. **`claude/` root permissions are unproven** (§4, last checkbox).

---
## 8. Working rules

Every rehearsal goes to `/tmp`; `/sdf/group/lcls/ds/dm/apps/` stays read-only until §5.
Never modify the 17 external repos — `/tmp/mhr-staging` is pristine reference, rehearse
against the `/tmp/mhr-work/staging` copy. Never `git add -A` / `git commit -a` here (§4).
Host toolchain: bash 4.4.20 (not 5), jq 1.6 (not 1.7), rsync 3.1.3 (no `--mkpath`).
