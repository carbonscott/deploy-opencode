# Commit plan for the single-source / Claude-harness work

The `deploy-opencode` working tree on `sdfiana025` has **134 entries** in
`git status --porcelain -uall` and the last commit is `860ac10` from
**2026-08-14**. Nothing produced in this session has ever been committed. That
is the least reversible state the repo can be in: there is no restore point for
any of it, and it is mixed in with months of uncommitted human work.

This plan says what to commit, what to leave alone, and what to throw away. **It
does not commit anything.** The companion script `docs/commit-plan.sh` prints
its plan by default and only acts when given `--run`.

## How things were dated

Classification is by file mtime against the session boundary
**2026-08-26 15:20 (epoch 1787757600)**, cross-checked against `git log`
(`860ac10`, 2026-08-14 14:31) and the diff contents. The split is unusually
clean: every session artefact has an mtime between 15:22 and 16:40 on
2026-08-26, and the next most recent entry is from 2026-06-25. Nothing had to be
guessed.

The one case mtime cannot date is a **deleted** file, which has no mtime. The
eight `D claude/skills/<name>/SKILL.md` deletions are session work — `migrate.sh`
moved those bodies to `src/<name>/` — and are classified by content, not date.

## Counts

| Category | Entries |
| --- | --- |
| (a) this session's single-source / renderer / claude-harness work | **56** |
| (a7) shared-binary work, added 2026-08-28 | **10** (3 new, 7 modified) |
| (b) pre-existing human work, untouched | **35** |
| (c1) junk — recommend not committing | **13** |
| (c2) externally-managed copies — recommend `.gitignore`, not commit | **30** |
| total accounted | **134** = 56 + 35 + 13 + 30 |

The (a7) row is deliberately outside that sum. It was added on 2026-08-28,
after the 134-entry snapshot: 3 of its files are new since then, and the other
7 were already counted in (a) and were simply modified again. The 134 still
describes the working tree as it stood on 2026-08-26.

---

## (a) Session work — seven commits

### Commit 1 — `Render skills from one source into both harness trees`

```
render.sh
migrate.sh
docs/design-single-source-skills.md
docs/render-equivalence-report.md
```

*Why:* a skill body had to be maintained twice, once under `opencode/skills/`
and once under `claude/skills/`, and the two drifted. `render.sh` makes one
`src/<name>/` the source and both harness trees build outputs; `migrate.sh` moves
an existing skill into that shape. The equivalence report is the evidence that
the render reproduces what was there before.

### Commit 2 — `Move the eight alignment skills to src/ as their single source`

```
src/align/  src/approval/  src/breakdown/  src/clarify/
src/handoff/  src/latent-demand/  src/no-eager/  src/no-op/     (16 files)
claude/skills/align/SKILL.md ... claude/skills/no-op/SKILL.md   (8 deletions)
claude/commands/*.md                                            (8 new)
opencode/commands/handoff.md  opencode/commands/latent-demand.md (2 modified)
```

*Why:* the first eight skills to actually go through `migrate.sh`, so the design
is proven on real content rather than fixtures. The `claude/skills/*/SKILL.md`
deletions are the other half of the move — committing the additions without them
would leave two copies of every body, which is the problem this removes. The two
`opencode/commands/` modifications are the renderer quoting `argument-hint`
consistently; they are output, not hand edits.

*Decision the human should make:* `claude/commands/*.md` and the rendered
`opencode/commands/*.md` are **build outputs**. They are committed here because
`opencode/commands/` is live hand-maintained state that other tooling reads
(`deploy.sh` explicitly declines to treat it as a deploy destination — design doc
§6), so removing it from the repo now would be a bigger change than this commit
should make. Once rendering is wired into deploy, both belong in `.gitignore`.

### Commit 3 — `Deploy a Claude Code tree alongside the opencode tree`

```
deploy.sh                          (modified)
claude/install-claude-lcls.sh
claude/settings.template.json
docs/claude-code-lcls-setup.md
docs/deploy-permissions.md
```

*Why:* the team is moving to Claude Code and the central deployment only
populated an opencode tree. `deploy.sh` now writes `$DEPLOY_ROOT/claude/` for
migrated repos, creating it with the right group rather than whatever `mkdir`
gives, and errors loudly on a repo matching neither layout instead of silently
shipping nothing. The install script and settings template are what a user points
at that tree with.

> **Note, 2026-08-28.** `claude/install-claude-lcls.sh` and
> `docs/claude-code-lcls-setup.md` were both modified again by the shared-binary
> work (Commit 7). Commit 3 should carry the versions as they stood before that;
> if the commits are made in one pass after the fact, fold these two files into
> Commit 7 instead of splitting them, rather than reconstructing an intermediate
> state nobody ever ran.

### Commit 4 — `Check deployed skills against their source for drift`

```
tools/skill-drift/env.sh
tools/skill-drift/scripts/skill-drift-cron.sh
docs/skill-drift-check.md
```

*Why:* the deployed `cuda-docs` skill was found three months stale — repo commit
`7da2b2d` (2026-05-17) bundled its docs and made paths skill-relative, and
`deploy.sh` was never re-run. Nothing noticed for three months. This renders each
skill from its repo and diffs against what is deployed. It is deliberately
read-only: a drift detector that self-heals hides the fact that someone is
editing deployed files.

### Commit 5 — `Add a backup and rollback path for the live deploy`

```
tools/deploy-backup/env.sh
tools/deploy-backup/scripts/deploy-backup.sh
docs/deploy-rollback.md
```

*Why:* `deploy.sh` rsyncs with `--delete` and has never been run against the live
tree. A bad first run could remove files with no way back. This captures the 160
entries / 513 KB `deploy.sh` can actually reach — permissions, setgid bits, group
ownership, symlinks and POSIX ACLs included — into a 157 KB archive stored off
the deploy tree, and restores it in half a second. Restore refuses by default and
needs two separate gates to touch production.

### Commit 6 — `Record what iterations 2-5 measured`

```
docs/iteration-2-report.md
docs/iteration-3-pilot-report.md
docs/iteration-4-report.md
docs/iteration-5-rehearsal.md
docs/askcode-merge-2026-08-26.md
docs/commit-plan.md
docs/commit-plan.sh
```

*Why:* the reports carry the measurements the design rests on — what was tested
against fixtures rather than reality, the askcode pilot, and the production drift
found along the way. Committed last so the code commits stay readable on their
own.

### Commit 7 — `Run claude-lcls on a shared team binary, not a personal install`

Added 2026-08-28, after the original six were planned.

```
tools/claude-binary/env.sh                          (new)
tools/claude-binary/scripts/publish-claude-binary.sh (new)
docs/claude-binary-publish.md                       (new)
claude/install-claude-lcls.sh                       (modified)
docs/claude-code-lcls-setup.md                      (modified)
docs/claude-lcls-second-user-handoff.md             (modified)
docs/deploy-rollback.md                             (modified)
docs/deploy-permissions.md                          (modified)
tools/deploy-backup/scripts/deploy-backup.sh        (modified)
.gitignore                                          (modified)
```

*Why:* `install-claude-lcls.sh` required a personal Claude Code install and
refused to run without one, so 17 deployed skills reached only people who had
already installed the harness themselves — and the `~/.local/bin/claude` launcher
shim was observed vanishing from a home directory, leaving `claude-lcls`
installed and unable to start (claims C17, C22). One binary is now published for
`ps-users` at `dev/claude/bin/`, and the installer resolves that and nothing
else: the personal-install fallbacks are removed, not reordered. The doc changes
are the ripple — three of them correct statements that this work made false,
including the second-user handoff's "Route A DOES NOT WORK", which is now the
recommended route.

*Note on `deploy.sh`:* deliberately **not** modified. The binary is not a skill,
and the standing instruction was not to grow a `bin/` target there. Publishing is
a separate tool.

*Note on `.gitignore`:* `claude/bin/` is added so the 330 MB binary can never be
committed. This repo has never carried binaries (see (c1) below) and must not
start.

---

## (b) Pre-existing human work — 35 entries, NOT TOUCHED

**None of these appear in any commit above.** They were all last modified between
2026-02-27 and 2026-06-25, months before this session, and they are not this
work's to decide about. They stay exactly as they are, uncommitted, for their
author to handle:

Modified:
```
claude/skills/find-rings/scripts/deploy-find-rings.sh     2026-06-25
claude/skills/nano-isaac/scripts/deploy-nano-isaac.sh     2026-06-25
opencode/skills/find-rings/scripts/deploy-find-rings.sh   2026-06-25
opencode/skills/nano-isaac/scripts/deploy-nano-isaac.sh   2026-06-25
opencode/opencode.json                                     2026-05-31
opencode/skills/ask-s3df/SKILL.md                          2026-04-10
```

Untracked:
```
claude/skills/ask-slac-ai-tools/                           2026-05-07
claude/skills/research-loop/SKILL.md                       2026-03-12
claude/skills/research-loop/references/inner-loop-protocol.md
claude/skills/research-loop/references/onboarding-questions.md
claude/skills/research-loop/references/outer-loop-protocol.md
claude/skills/research-loop/references/scaffolding.md
commands/align.md  commands/approval.md  commands/be-concise.md
commands/breakdown.md  commands/clarify.md  commands/gaps.md
commands/handoff.md  commands/latent-demand.md  commands/no-op.md
commands/taskify.md                                        2026-04-25
docs/apptainer-container-assessment.md                     2026-03-13
docs/apptainer-hybrid-container.md                         2026-03-13
docs/claude-code-as-harness.md                             2026-06-26
docs/creating-code-skills.md                               2026-03-03
docs/lcls-bedrock-use-case.md                              2026-03-05
docs/opencode-sandbox-access-gaps-2026-04-23.md            2026-04-24
memory/opencode-tools-overview.md                          2026-02-27
memory/slide-instructions.md                               2026-02-27
opencode/agents/smartsheet                                 2026-03-24
opencode/skills/smartsheet/SKILL.md                        2026-03-24
opencode/skills/docs-search/facility-env.sh                2026-03-12
tools/check-spending-slac.sh                               2026-06-01
tools/fix-key-perms.sh                                     2026-06-25
```

Two of these deserve a look from their author, though this plan does not act on
them: `tools/fix-key-perms.sh` is referenced by `CLAUDE.md` as the way to
re-assert API-key permissions but is not in the repo, and the top-level
`commands/` directory duplicates skills that now live in `src/`.

---

## (c1) Junk — 13 entries, recommend NOT committing

The human decides; the script will not touch these.

| Path | Age | Recommendation |
| --- | --- | --- |
| `sandbox/opencode-sandbox.sif` | 2026-03-13, **43 MB** | `.gitignore`. A container image in git history is permanent and this repo has never carried binaries. Rebuild it from a definition instead. |
| `opencode/opencode.json.bak` | 2026-04-14 | delete — `opencode.json` is tracked, git is the backup |
| `opencode/opencode.json.bak2` | 2026-04-16 | delete, same reason |
| `opencode/opencode.json.bak3` | 2026-04-16 | delete, same reason |
| `opencode/opencode.json.bak-20260531` | 2026-05-31 | delete, same reason |
| `opencode/agents/elog-copilot.md.bak.20260420-162156` | 2026-04-20 | delete |
| `claude/skills/elog-copilot/SKILL.md.bak` | 2026-04-20 | delete |
| `zarr_direct_test.py` | 2026-04-11 | scratch experiment at repo root — move out or delete |
| `zarr_experiment.py` | 2026-04-11 | same |
| `zarr_exp_v2.py` | 2026-04-11 | same |
| `zarr_tiled_test.py` | 2026-04-11 | same |
| `profile_mode_b.py` | 2026-04-11 | same |
| `test.md` | 2026-03-31, 24 KB | scratch — read it once, then delete |

Note the pattern: four generations of `opencode.json.bak*` exist because nothing
was ever committed. Committing removes the reason to keep making them.

## (c2) Externally-managed copies — 30 entries, recommend `.gitignore`

Commit `5df0e9b` ("Stop tracking ask-epics and ask-s3df; manage as independent
repos") took these skills out of the repo, and `.gitignore` has entries for the
`claude/skills/` side — but not the `opencode/skills/` side or the
`opencode/agents/` symlinks. So they show up as untracked forever:

```
opencode/skills/ask-epics/{SKILL.md,env.sh,setup.sh,bin/docs-index,bin/docs-index.py}
opencode/skills/ask-nersc/{SKILL.md,env.sh,setup.sh,bin/docs-index,bin/docs-index.py}
opencode/skills/ask-olcf/{SKILL.md,env.sh,setup.sh,facility-env.sh,bin/docs-index,bin/docs-index.py}
opencode/skills/ask-s3df/{env.sh,setup.sh,bin/docs-index,bin/docs-index.py}
opencode/skills/ask-tiled/{SKILL.md,env.sh,setup.sh,bin/docs-index,bin/docs-index.py}
opencode/agents/{ask-epics,ask-nersc,ask-olcf,ask-tiled,xpm-seq}
```

Proposed `.gitignore` additions (the human's call; this plan does not edit
`.gitignore`, and note that `opencode/skills/ask-s3df/SKILL.md` is still
*tracked* and modified, so ignoring the whole directory needs a
`git rm --cached` first):

```
# Nested standalone skill repos — opencode side (mirrors the claude/ entries above)
opencode/skills/ask-epics/
opencode/skills/ask-nersc/
opencode/skills/ask-olcf/
opencode/skills/ask-tiled/
opencode/agents/ask-epics
opencode/agents/ask-nersc
opencode/agents/ask-olcf
opencode/agents/ask-tiled
opencode/agents/xpm-seq

# Container image — rebuild, don't version
sandbox/*.sif
```

`.gitignore` already covers `.claude/settings.local.json`, `opencode/node_modules/`,
`opencode/package.json`, `opencode/bun.lock`, `proxy/run/`,
`.confluence_progress.json`, `confluence_export.log`, `*.swp`, `externals/`,
`opencode/skills/xpm-seq/`, and `claude/skills/ask-{tiled,s3df,epics,nersc,olcf}/`.
It does **not** cover any rendered output tree. It should not yet — see the
decision noted under Commit 2 — but that is the next `.gitignore` change after
rendering is wired into deploy.

---

## Why this matters for the deploy work

The deploy work about to happen writes to a shared tree that fifteen-odd people
read. `tools/deploy-backup/` makes the *deployed* tree reversible. Committing
makes the *source* reversible, and the two are useless apart:

- **A rollback needs something to roll back to.** `deploy-backup restore` puts
  the old deployment back, but if the render that produced the bad deployment
  came from an uncommitted `render.sh`, you cannot reproduce the good one either.
  You would have a working deployment and no way to rebuild it.
- **`skill-drift` compares deployed against source.** With an uncommitted source,
  "the source" is whatever happens to be in one directory on one host. There is
  no revision to name in a report and no way to tell whether the source or the
  deployment moved.
- **A commit is a cheap checkpoint; a 43 MB `.sif` and four `.bak` generations
  are the expensive substitute.** The `.bak` files in (c1) exist precisely
  because there was no other undo.
- **`deploy.sh` reads `skills.manifest.json` from a working tree.** The first
  real deploy will be attributed to whatever that tree contained at the time. If
  that state is uncommitted, the deploy is unattributable and the next one is
  unrepeatable.

Commit first, then deploy. Not the other way round.

## Running it

```bash
cd /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode
./docs/commit-plan.sh            # prints the plan, verifies paths, writes nothing
./docs/commit-plan.sh --run      # creates a branch and makes the six commits
```

The script creates a branch (`iteration-5-single-source` by default) before
committing, because `main` is already 5 commits ahead of `origin/main` and this
work should be reviewable separately. It never runs `git push`. It refuses if a
commit's paths are missing, and it skips a commit whose paths are already staged
clean rather than making an empty one.
