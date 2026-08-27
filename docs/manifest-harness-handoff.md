# Manifest-harness change — handoff

**Status:** implemented, rehearsed in `/tmp`, **committed on a topic branch, NOT pushed, NOT deployed.**
**Branch:** `feat/manifest-harness-render` (two commits on top of `main` @ `860ac10`):
`5e9a05e` the manifest-harness change itself, then a second commit carrying the three
deployment-blocker fixes (cron guard, cuda-docs SHA pin, docs). `main` has not moved.
**Date:** 2026-08-27.

**If you read only one thing:** a bare `./deploy.sh` **no longer exits 0.** It deploys the
12 cron-free skills and **hard-refuses** the five ps-data cron skills with exit code `3`.
That is deliberate — see §6.
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
| `deploy.sh` | 813 | tracked | `has_harness` TSV column; `write_harness_meta()` + cleanup trap; `resolve_harness_source()`; dry-run no longer mkdirs. **Second commit adds** `assert_cron_group_safe()` (the ps-data guard, §6), `is_sha_ref()` + a SHA clone/update path (§9), and a 6th TSV column `cron_script`. 572 → 813 lines. |
| `render.sh` | 429 | tracked | `--meta` flag; `skill.json` demoted to fallback; frontmatter stripping at all 4 call sites. Unchanged by the second commit. |
| `validate-manifest.sh` | 285 | tracked | validates the manifest. Unchanged by the second commit; still exits `0` (17 pre-existing `description_menu > 120 chars` warnings). |
| `docs/design-manifest-harness.md` | 1449+ | tracked | the spec. Its AS BUILT section carries the guard and SHA-ref detail. |

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
- [ ] Cron hazard handled — see §6. This is the one that can hurt 3687 people. It is now
      enforced by a deploy-time guard, so the failure mode is a loud exit `3`, not a silent
      revert. Do not treat that exit `3` as a bug to route around.
- [x] Committed: `5e9a05e` (manifest-harness) + a second commit (blocker fixes + docs) on
      `feat/manifest-harness-render`. Every path was named explicitly; **never `git add -A`** —
      the working tree holds ~78 unrelated human changes (`memory/`, `research-loop/`,
      apptainer + bedrock docs, `.bak` files, a 43 MB `.sif`, `migrate.sh`). Nothing pushed.
- [ ] Decide `DEPLOY_CLAUDE`. It defaults to `1`, so the **first real deploy creates
      `$DEPLOY_ROOT/claude/`** via an `ensure_claude_root()` path only ever exercised against a
      fake root. A wrong group or stray `other::r-x` there is the 2026-02-12 incident.
      Consider `DEPLOY_CLAUDE=0` for the first run.

---
## 5. Recommended first live deploy

**Revised for the cron guard.** A bare `./deploy.sh` now exits `3`: the five cron skills are
refused before a single byte is written for them, the other 12 deploy normally. So there is no
longer any way to *accidentally* revert the cron scripts — but there is also no bare-deploy
green run until the five upstream repos are fixed.

```sh
cd /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode

# 0. Validate. Must exit 0.
./validate-manifest.sh ; echo "exit=$?"

# 1. Dry run against the real root. Writes nothing.
DRY_RUN=1 ./deploy.sh

# 2. One skill, opencode only, to prove the pipeline end to end.
#    cuda-docs is pinned (§9) so this is a provable no-op on bytes:
#    the deployed SKILL.md must stay md5 ecf3dfbe1137e04c91bfa80d3f41a04e, 2541 bytes,
#    and NO docs/ directory may appear.
DEPLOY_CLAUDE=0 ./deploy.sh cuda-docs
md5sum /sdf/group/lcls/ds/dm/apps/dev/opencode/skills/cuda-docs/SKILL.md
ls     /sdf/group/lcls/ds/dm/apps/dev/opencode/skills/cuda-docs/
#    Then actually invoke the skill in a harness. Nobody has ever done this (§7.3).

# 3. THE 12 DEPLOYABLE SKILLS — the exact command a human runs today.
#    Naming them explicitly is what makes this exit 0 instead of 3.
DEPLOY_CLAUDE=0 ./deploy.sh cuda-docs ask-ami ask-lcls2 ask-slac-ai-tools \
  ask-slurm-s3df ask-smalldata askcode confluence-search docs-search \
  elog-search experimental-hutch-python xpm-seq
#    Expected: exit 0, zero ERROR and zero WARN lines, no tools/ tree created
#    (none of the 12 ships a tools/ directory).

# 4. Re-run step 3 with DEPLOY_CLAUDE=1 once the claude/ root permissions are
#    inspected by hand (§10 proves the mode arithmetic, not the live filesystem).

# 5. The five cron skills — ONLY after §6 is resolved upstream. Until then the
#    guard refuses them and that is the correct outcome; do not work around it.
```

Running a bare `./deploy.sh` is still safe — it just exits `3` after deploying the 12 and
printing five `DEPLOY REFUSED` blocks. Exit `3` in that situation means "the guard did its
job", not "the deploy broke". Check the log before reacting to it.

---
## 6. Cron hazard — READ THIS

**Re-verified 2026-08-27. Still real, five for five.** Pre-existing; this change neither
causes nor cures it. A deploy would trigger it, so a deploy-time guard now blocks it.

`skill-ask-{epics,nersc,s3df,tiled,olcf}` each carry one divergent line. The repo's `main`
says `chgrp -R ps-data`; the live deployed script says `ps-users`:

| repo / clone dir | tools dir | line | repo `main` | live |
|---|---|---|---|---|
| `skill-ask-epics` / `ask-epics` | `epics-docs` | 51 | `ps-data` | `ps-users` |
| `skill-ask-nersc` / `ask-nersc` | `nersc-docs` | 37 | `ps-data` | `ps-users` |
| `skill-ask-s3df` / `ask-s3df` | `sdf-docs` | 38 | `ps-data` | `ps-users` |
| `skill-ask-tiled` / `ask-tiled` | `tiled-docs` | 37 | `ps-data` | `ps-users` |
| `skill-ask-olcf` / `ask-olcf` | `olcf-docs` | 38 | `ps-data` | `ps-users` |

**Impact.** `deploy.sh` rsyncs `tools/` unconditionally, so deploying any of the five would
revert its cron script. The next cron fire re-chgrps that corpus from `ps-users` (**3748**
members) to `ps-data` (**61**) — 3687 people lose read access, per corpus. `ps-users` and
`ps-data` are **not** nested. **`sdf-docs` is hourly**
(`CRON_SCHEDULE="${CRON_SCHEDULE:-0 * * * *}"` on `sdfcron001`), so first damage lands within
the hour. It is not latent.

### 6.1 The deploy-time guard (shipped)

`deploy.sh` now refuses to deploy a skill whose cron script still contains the ps-data
`chgrp`. `assert_cron_group_safe()` runs inside `deploy_skill()` immediately after the clone
and **before** every write: before `write_harness_meta()`, before `render.sh`, before the
skill rsync, before the `claude/` rsync, before the `agents/` symlink, and before the
`tools/` rsync. On a hit it prints a `DEPLOY REFUSED` block naming the file, the offending
line with its line number, and the remedy; sets `DEPLOY_FAILED=1`; and returns without
writing a byte for that skill. `main()` turns `DEPLOY_FAILED` into **exit 3**. Other skills
deploy normally in the same run.

It reads the cron script named by a new manifest column, `.cron.script`, so it only ever
scans the five entries with a non-null `cron` block. It keys on **content, not on the five
names** — rehearsed by pointing one clone at a locally fixed copy reading `ps-users`, which
then deployed cleanly (exit 0) while its siblings were still refused.

Three deliberate design points:

- **Fail-closed on a missing script.** If the manifest names a `cron.script` the clone does
  not have, that is an **ERROR**, not a warning. A warning would let one upstream rename
  silently disable the check while the `tools/` rsync still shipped whatever script *is* in
  the repo — exactly the silent regression the guard exists to stop.
- **Path containment.** An absolute or `..`-containing `cron.script` is rejected, so a bad
  manifest value cannot point the scan at the already-correct **live** copy and pass.
- **No escape hatch.** There is no `ALLOW_PS_DATA_CRON`, no flag, no environment variable.
  The only way past the guard is to fix the cron script upstream. This is intentional: an
  override would be used once in a hurry and that once is the incident.

### 6.2 The remedy — exactly what a human does

The fix is one commit per repo, already written but **committed-and-unpushed**, so a
`deploy.sh` that clones from GitHub cannot see it:

```
/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/iter6-cron-fix/skill-ask-{epics,nersc,s3df,tiled,olcf}
branch: fix/cron-chgrp-ps-users        subject: Fix cron chgrp target: ps-data -> ps-users
```

For each of the five: **push that branch and merge it to `main`** on the upstream GitHub
repo. Pushing alone is not enough — `deploy.sh` clones the `ref` in the manifest, which is
`main`. Then re-run the deploy; the guard will pass and the five will deploy.

Pre-flight assertion — for each of the five, this must print `1` before you proceed:

```sh
grep -c 'chgrp -R ps-users' <clone>/tools/<x>-docs/scripts/<x>-docs-cron.sh
```

**In the meantime**, deploy the other 12 by explicit name — §5 step 3.

### 6.3 THE STACKED EXEC-BIT TRAP — do not cherry-pick

`tiled-docs-cron.sh` and `olcf-docs-cron.sh` are mode **0644**, while their three siblings
are **0755**. Measured on both sides:

| cron script | repo mode | live mode |
|---|---|---|
| `epics-docs/scripts/epics-docs-cron.sh` | 755 | 755 |
| `nersc-docs/scripts/nersc-docs-cron.sh` | 755 | 755 |
| `sdf-docs/scripts/sdf-docs-cron.sh` | 755 | 755 |
| `tiled-docs/scripts/tiled-docs-cron.sh` | **644** | **644** |
| `olcf-docs/scripts/olcf-docs-cron.sh` | **644** | **644** |

A non-executable cron script does not run. **The tiled-docs cron has therefore never once
succeeded** — and the same is true of olcf-docs. `rsync -a` preserves the mode, so a deploy
neither fixes nor worsens it.

That is why the exec-bit fix is **stacked ON TOP of the chgrp fix, on purpose**, in the
`fix/cron-chgrp-ps-users` branches. The two are not independent:

> **Taking the exec-bit fix alone resurrects a dead cron that writes `ps-data`.**

Today those two crons are inert, which is the only reason their `ps-data` line has not
already cost anyone access. `chmod +x` them without the `ps-users` line and you take two
corpora that are currently *not* being damaged and start damaging them on the next tick.

**Rule: never cherry-pick the exec-bit commit by itself.** Merge the branch whole, chgrp fix
first, or merge neither. If someone hands you "just the one-line chmod", refuse it.

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

---
## 9. Pinned ref: cuda-docs (blocker 2)

`skills.manifest.json` is JSON and cannot carry comments, so the pin is documented here.

**The pin.** The `cuda-docs` entry's `"ref"` is `"421f3df7f1dbc20b4f581aa438eba802e7d3d4f4"`
("Initial: cuda-docs knowledge wrapper", 2026-05-12), not `"main"`. This is deliberate and
current — it is NOT a stale ref somebody forgot to bump.

**Why.** Upstream `carbonscott/skill-cuda-docs` moved to HEAD `7da2b2d` ("Bundle CUDA docs and
make data path skill-relative", 2026-05-17), which rewrote `SKILL.md` (2541 -> 2779 bytes) and
added ~2.5 MB of `docs/*.md`, taking the skill off the `central_data` path the manifest still
names (`/sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs`). The LIVE deployed
`opencode/skills/cuda-docs/` is a single `SKILL.md`, md5 `ecf3dfbe1137e04c91bfa80d3f41a04e`,
2541 bytes, which is byte-identical to `421f3df`. Pinning to `421f3df` therefore makes this
deploy a genuine no-op for cuda-docs instead of smuggling a content upgrade in with a harness
refactor. `421f3df` is exactly 1 commit behind `main`/`7da2b2d`.

**How to un-pin.** One line: set the entry's `"ref"` back to `"main"` (or to a newer SHA).
Doing so is not a cosmetic change — it accepts the rewritten `SKILL.md` body plus the ~2.5 MB
`docs/` bundle, and it requires revisiting `central_data`, because the bundled skill reads its
docs from a skill-relative path and no longer uses the central data directory the manifest
points at. Treat the upgrade as its own deliberate change with its own rehearsal and diff review.

**SHA-ref support, and end-to-end verification.** `deploy.sh` originally cloned with
`git clone --depth=1 -b "$ref"`, which cannot take a SHA. The second commit adds
`is_sha_ref()` (full 40-character lowercase hex only) and a matching clone/update path:
`git init` + `remote add` + `fetch --depth=1 origin <sha>` + `checkout --detach FETCH_HEAD`
on a fresh clone, and `fetch --depth=1 origin <sha>` + `checkout --force --detach FETCH_HEAD`
on an update. The forced detached checkout also recovers a staging clone an earlier run left
attached to a branch. Verified on the host, not assumed: a shallow fetch of a **non-tip**
commit succeeds (`allowAnySHA1InWant` is on), and an **abbreviated** SHA is rejected by the
protocol (`fatal: couldn't find remote ref 524de15`) — which is why abbreviated hex is
deliberately routed down the branch path to fail loudly rather than being guessed at.

The pin is now verified **end to end**, not just statically. A fresh deploy of `cuda-docs`
into a throwaway root exits `0`, leaves the clone detached at `421f3df…`, contains **no
`docs/` directory anywhere**, and `diff -r` against the frozen live snapshot reports the
deployed `opencode/skills/cuda-docs` and `claude/skills/cuda-docs` **byte-identical to live**
(md5 `ecf3dfbe1137e04c91bfa80d3f41a04e`, 2541 B). Blocker 2 is a genuine no-op. The ref also
round-trips: SHA → branch and branch → SHA both land on the right HEAD.

---
## 10. Permission parity rehearsal (blocker 3) — what it did and did not prove

The `claude/` root permissions were previously untestable because `/tmp` was assumed not to
reproduce the live filesystem's ACLs. That assumption was wrong: `/tmp` on this host is **xfs
and does support POSIX ACLs**, so a faithful parity root was built and the test finally ran.

**The parity root.** `/tmp/mhr-build-parity.sh` builds a root that is `chgrp ps-data` +
`chmod 2775` + the live default ACL (`setfacl` access and default), pre-seeded with an
`opencode/agents` shaped like live. `getfacl` on the mock and on live `dev/` is **byte-
identical, every access and default entry** — including the `default:other::r-x` that is the
whole reason `ensure_claude_root()` must set an absolute `2750` rather than a `chmod g+rX`
that can only add bits.

### PROVEN

- **`ensure_claude_root()`'s absolute `2750` is correct under the real default ACL.** This is
  the first time that has actually been demonstrated. `claude/` and `claude/skills/` both come
  out `drwxr-s--- 2750 cwang31:ps-users`, with `getfacl` byte-identical to live `dev/opencode`
  (`mask::r-x`, `other::---`, full default ACL inherited).
- **The setgid trap and its remedy.** Demonstrated directly on a real `ps-data → ps-users`
  chgrp: `chgrp` **clears** setgid on every directory it touches; a following `chmod -R g+rX`
  does **not** restore it; only `rsync_and_chmod()`'s `find "$dst" -type d -exec chmod g+s {} +`
  restores it. Instrumented probes inside a patched copy of `deploy.sh` show
  `before chgrp: setgid-dirs=0/1 → after chgrp: 0/1 → after g+s: 1/1`, and at full scale
  **54/54 directories setgid, 0 non-setgid**. The ordering is load-bearing and it works.
- **The `chgrp` is load-bearing on *every* deploy, not just the first.** Unexpected finding
  from the instrumentation: the group before `chgrp` is `gu`, not `ps-users`, even though
  `mkdir` under the setgid parent *does* inherit `ps-users`. Cause: `rsync -a` implies `-g`
  and the staging tree is `cwang31:gu`, so rsync actively reverts the destination directory to
  `gu` and strips setgid on every run.
- **Nothing leaks.** The only four non-other-readable directories are `opencode/`,
  `opencode/agents/`, `claude/`, `claude/skills/`; all files are `o+r` and all skill dirs
  `o+rx`, identical to live, with access gated one level up by `other::---`. The recorded
  audit command produces **no output**:
  `find <root> -path '*/env' -prune -o \( ! -perm -o+r ! -group ps-users -printf '%u %p\n' \)`
- **The guard's blast radius.** A full 17-entry run into the parity root exits `3`, refuses
  exactly the five, writes nothing for them, and **creates no `tools/` tree at all** — the only
  five repos carrying `tools/` are precisely the five refused.

### ONE REAL FINDING — `opencode/skills/` on a *fresh* root

Created by `rsync_and_chmod()`'s bare `mkdir -p`, it comes out **`drwxrwsr-x 2775`** (group-
writable, `other::r-x`) because it takes `other::r-x` and `mask::rwx` straight from the
inherited default ACL, and `chmod -R g+rX` only ever *adds* bits. Live is `drwxr-s--- 2750`.
This is the exact failure mode `ensure_claude_root()` exists to prevent, and **there is no
equivalent guard on the opencode side.**

In production it is **latent, not active**: live `opencode/skills` already exists at `2750`
and `rsync_and_chmod()` never clears bits, so this deploy will not change it. It bites only if
`opencode/skills` is ever recreated from scratch — a fresh `DEPLOY_ROOT`, a restore, a new
environment. **Recommendation:** give `SKILLS_DST` / `AGENTS_DST` / `TOOLS_DST` the same
`ensure_*_root()` absolute-mode treatment the `claude/` tree already gets. Not done in this
commit.

### NOT PROVEN — the residual gaps

1. **Owner `psdatmgr`.** Live `dev/` is owned by `psdatmgr`; the mock is owned by `cwang31`,
   and `chown` needs root. So the case where `chgrp`/`chmod` are attempted on a directory the
   deployer does **not** own — precisely what `ensure_claude_root()`'s `2>/dev/null || WARN`
   fallbacks exist for — is untested. The first real deploy will own the `claude/` it creates,
   so this should not bite, but it is inferred.
2. **The pre-existing live `opencode/skills` at `2750`.** The mock creates it fresh, so only
   the fresh-creation mode was observed (the finding above). The pre-existing path is safe by
   the "chmod never clears bits" argument, but it was not measured.
3. **Effective access as a non-member.** The deployer is in both `ps-data` and `ps-users`, so
   it is not empirically confirmed that one of the 3689 `ps-users`-but-not-`ps-data` members
   can read the tree, nor that a non-member cannot. That is a mode/ACL argument, not a
   measurement.
4. **Filesystem class.** `/tmp` is xfs; live is a different (GPFS/Weka-class) store. ACL
   semantics matched exactly here, but inheritance on the real backing store is asserted by
   equivalence, not measured.
5. **The five blocked skills' deploy path is entirely untested end to end** — by construction.
   Until `fix/cron-chgrp-ps-users` is pushed and merged, no rehearsal can exercise the `tools/`
   rsync, `TOOLS_DST` creation, or those skills' permissions. **This is the largest remaining
   untested surface**, and it is exactly the surface the cron incident lives on.

## DEPLOYED — 2026-08-27

**What ran:** `./deploy.sh` against the live root `/sdf/group/lcls/ds/dm/apps/dev`, in two
stages, naming skills explicitly — stage one `DEPLOY_CLAUDE=0` (exit 0), stage two
`DEPLOY_CLAUDE=1` (exit 0). Logs: `/tmp/mhr-deploy-stage1.log`, `/tmp/mhr-deploy-stage2.log`.

**Deployed (12, `cron: null`):** cuda-docs (pinned SHA `421f3df7`), ask-ami, ask-lcls2,
ask-smalldata, ask-slurm-s3df, ask-slac-ai-tools, askcode, docs-search,
experimental-hutch-python, xpm-seq, confluence-search, elog-search.

**NOT deployed (5, `cron` non-null):** ask-epics, ask-nersc, ask-s3df, ask-tiled, ask-olcf.
Their manifest `ref` is `main`, and `main` upstream still carries `chgrp -R ps-data`. The
ps-data guard would hard-refuse them, so they were never named. Verified byte-identical to the
pre-deploy backup after both stages.

**What changed in live** (independently re-derived: full md5 inventory of `dev/opencode` vs
the backup, plus `rsync -aHAXni --checksum --delete` over `dev/tools`):

- 0 paths added, **0 paths removed**, 7 files content-changed — all `SKILL.md`:
  ask-ami, askcode, ask-lcls2, ask-slurm-s3df, ask-smalldata, experimental-hutch-python,
  xpm-seq. Frontmatter reserialized only (quoting style / folded scalars flattened);
  **all 7 bodies byte-identical** to the backup after frontmatter stripping. The other five
  SKILL.md files and every non-SKILL.md file are byte-identical.
- 25 directories gained the setgid bit (`755` → `2755`): the 12 managed skill directories
  **and their 13 subdirectories**. No owner or group changed anywhere.
- New tree `dev/claude/`: 42 files, 27 directories, 0 symlinks.
  `drwxr-s--- 2750 cwang31:ps-users` for `claude/` and `claude/skills/`; the 12 skill
  directories under it are `2755 cwang31:ps-users`. Its ACL is byte-identical to
  `dev/opencode`. Content and modes match the opencode side exactly. No `claude/agents/`.
- `dev/tools` untouched (rsync itemization empty). `commands/`, `opencode.json`, `agents/`
  symlinks, `node_modules/`, and the three hand-managed skills (lcls-catalog 2750,
  smartsheet 2750, token-usage 2775) all unchanged.
- Audit command over `dev/opencode` and `dev/claude`: both empty — clean.

**Backup / rollback.** `/tmp/mhr-predeploy/` (`opencode/`, `tools/`, 31,746-line
`inventory.tsv`), taken with `rsync -aHAX` immediately pre-deploy. It lives on `/tmp` and is
not durable.

```sh
rm -rf /sdf/group/lcls/ds/dm/apps/dev/claude
rsync -aHAX --delete /tmp/mhr-predeploy/opencode/ /sdf/group/lcls/ds/dm/apps/dev/opencode/
rsync -aHAX --delete /tmp/mhr-predeploy/tools/    /sdf/group/lcls/ds/dm/apps/dev/tools/
```

**Outstanding.**

1. **The five cron skills need a MERGE to `main` upstream.** `fix/cron-chgrp-ps-users` was
   pushed on skill-ask-{epics,nersc,s3df} only; skill-ask-{olcf,tiled} were held back because
   their branch tip also flips the cron script's mode `100644` → `100755`, a behavioral change
   beyond the chgrp fix. A pushed branch is invisible to `deploy.sh`, which clones the
   manifest `ref` (`main`). Until the merge lands, those five stay refused — correctly.
2. **The `2775`-on-fresh-creation finding is still latent.** `SKILLS_DST`/`AGENTS_DST`/
   `TOOLS_DST` still lack the absolute-mode `ensure_*_root()` treatment `claude/` gets. Not
   triggered here because `opencode/skills` already existed; it bites on a fresh `DEPLOY_ROOT`.
3. **Skill invocation is still untested end to end.** Nothing has loaded a skill from either
   `dev/opencode/skills/` or the new `dev/claude/skills/` since the deploy. Cron entries were
   not installed; no crontab was touched.
