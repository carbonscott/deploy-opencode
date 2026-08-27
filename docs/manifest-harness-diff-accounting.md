# Rehearsal vs. Live — full difference accounting

Compared: `/tmp/mhr-mock-deploy/opencode` (rehearsed, iteration-2 manifest-harness deploy.sh)
      vs: `/tmp/mhr-live-snapshot/opencode` (frozen read-only copy of the live deployed tree)

Method: `find`-based path sets on both sides, `comm` for set difference, `cmp` per common
regular file, `readlink` per common symlink, `stat -c %a`/`%G` per common path, plus a
frontmatter/body splitter for every `SKILL.md`. Nothing under `/sdf/group/lcls/ds/dm/apps/`
was read or written during this step; only the frozen `/tmp` snapshot was used.

---

## HEADLINE

**Does deploying this change any live skill BODY text?  YES — for exactly one skill, `cuda-docs`,
and NOT because of the manifest-harness change.**

- 16 of 17 managed skills: body byte-identical to live. Only the YAML frontmatter is
  reserialized, and it parses to the identical `{name, description}` on both sides.
- `cuda-docs`: the body differs. Verified cause — the **upstream repo**
  (`carbonscott/skill-cuda-docs`, HEAD `7da2b2d` "Bundle CUDA docs and make data path
  skill-relative") changed the skill: the docs were moved into the repo as
  `docs/{best-practices,driver-api,runtime-api}.md` (2.5 MB) and the SKILL.md body was
  rewritten to resolve `$CUDA_DOCS` relative to the skill dir instead of hard-coding
  `/sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs`.
  This is **upstream drift since the live deploy of 2026-05-12**, not a harness artifact:
  in the pristine clone, `opencode/skills/cuda-docs/SKILL.md` and
  `claude/skills/cuda-docs/SKILL.md` are byte-identical (both md5 `e7cd1eb8…`), so the OLD
  deploy path would render exactly the same new body. The harness change is body-neutral for
  all 17 skills.
  **Decision required before the live run:** a real deploy will replace the live
  `cuda-docs/SKILL.md` and add 2.5 MB of bundled docs, switching the skill off the central
  data dir named in `skills.manifest.json` (`central_data`). Intended by upstream — but
  confirm it is intended by *this* deploy.

No other body text changes. No asset content changes. No missing assets.

---

## 1. Raw comparison and named exclusions

| side | files | dirs | symlinks | total paths |
|---|---|---|---|---|
| rehearsal `A` | 75 | 39 (incl. root) | 17 | 130 (excl. root) |
| live `B`, excluding exclusions | 104 | 42 (incl. root) | 20 | 165 (excl. root) |

**Named exclusions (live-only bulk trees deploy.sh does not own), excluded from per-path accounting:**

- `node_modules/` — **3663 paths: 3428 regular files, 228 directories, 7 symlinks** (~57 MB).
  Installed by `bun`/`npm` for the opencode runtime. `deploy.sh` never reads or writes it.
  This is the only bulk exclusion; everything else is accounted for path-by-path below.

**Common paths compared: 126.**

**Totals of differing paths (excluding `node_modules`): 103**
- only-in-rehearsal: **4**
- only-in-live: **39**
- present in both, CONTENT differs: **8** (all `SKILL.md`)
- present in both, MODE/GROUP differs: **52** (35 managed dirs + 2 tree roots + 15 symlinks)
- present in both, identical in content and mode: **66**

(The content and mode buckets are disjoint: every content difference is a regular file, every
mode difference is a directory or symlink.)

---

## 2. Bucketed accounting, one line per path

### Bucket A — only-in-rehearsal (4 paths)

Rule: *present because the upstream skill repo gained content since the live tree was last deployed.*

| path | why intended |
|---|---|
| `skills/cuda-docs/docs` | New dir bundled by upstream commit `7da2b2d`; live predates it. |
| `skills/cuda-docs/docs/best-practices.md` | 212,986 B, shipped by upstream `7da2b2d`. |
| `skills/cuda-docs/docs/driver-api.md` | 1,229,298 B, shipped by upstream `7da2b2d`. |
| `skills/cuda-docs/docs/runtime-api.md` | 1,106,226 B, shipped by upstream `7da2b2d`. |

Not collapsed — only 4 paths, and they are the flagged headline item.

### Bucket B — only-in-live, not owned by deploy.sh (39 paths)

Rule: *hand-maintained state, or files owned by the opencode runtime; `deploy.sh` writes none of
these paths and a mock deploy therefore never creates them.*

Unmanaged skills (3 skills, collapsed 2 lines each = 6 paths):

| path | files collapsed | why intended |
|---|---|---|
| `skills/lcls-catalog/` (dir + `SKILL.md`) | 2 | Hand-managed skill; no manifest entry. |
| `skills/smartsheet/` (dir + `SKILL.md`) | 2 | Hand-managed skill; no manifest entry. |
| `skills/token-usage/` (dir + `SKILL.md`) | 2 | Hand-managed skill; no manifest entry. |
| `agents/lcls-catalog` | 1 symlink | Hand-made agent symlink for the above. |
| `agents/smartsheet` | 1 symlink | Hand-made agent symlink for the above. |
| `agents/token-usage` | 1 symlink | Hand-made agent symlink for the above. |

Hand-written agent prompt files (5 paths, listed individually):

| path | why intended |
|---|---|
| `agents/confluence-doc.md` | Hand-authored agent, not produced by any manifest entry. |
| `agents/daq-logs.md` | Hand-authored agent. |
| `agents/elog-copilot.md` | Hand-authored agent. |
| `agents/elog-copilot.md.bak.20260420-162156` | Hand-made backup of the above. |
| `agents/experimental-elog-copilot-postgres.md` | Hand-authored agent. |

opencode runtime / repo state (10 paths):

| path | why intended |
|---|---|
| `opencode.json` | Hand-maintained opencode config; deploy.sh never writes it. |
| `opencode.json.bak` | Hand-made backup. |
| `opencode.json.bak2` | Hand-made backup. |
| `opencode.json.bak3` | Hand-made backup. |
| `opencode.json.bak-20260531` | Hand-made backup. |
| `opencode.json.bak-20260612` | Hand-made backup. |
| `package.json` | opencode/bun runtime manifest. |
| `package-lock.json` | npm lockfile. |
| `bun.lock` | bun lockfile. |
| `.gitignore` | Hand-maintained (ignores `node_modules/`). |

Hand-maintained commands tree (collapsed, 15 paths = 1 dir + 14 files):

| path | files collapsed | why intended |
|---|---|---|
| `commands/` | 15 paths (`commands` dir + 14 `.md`: align, approval, be-concise, breakdown, clarify, formalize-plan, formalize-plan-delegated, gaps, handoff, lab-notebook-skill, latent-demand, no-eager, no-op, taskify) | Entirely hand-maintained slash commands. No manifest entry emits a `commands/` file, so the whole directory falls in this bucket for the same reason. |

Bucket B total: 6 + 5 + 10 + 15 = **39** ✔ matches the set difference.

### Bucket C — present in both, CONTENT differs (8 paths)

All 8 are `skills/<name>/SKILL.md`. Detailed in §3. Seven are frontmatter-reserialization only;
`cuda-docs` is the upstream body change flagged in the headline.

### Bucket D — present in both, MODE/GROUP differs (52 paths)

Three sub-rules:

1. **35 managed directories: rehearsal `2755 ps-users` vs live `755 ps-users`** — the 17 skill
   dirs plus their 18 subdirectories (`bin/`, `scripts/`, `references/`, `reference/`, `data/`,
   `schemas/`). **INTENDED and deliberate:** `rsync_and_chmod()` runs `chgrp -R $GROUP`, then
   `chmod -R g+rX`, then `find "$dst" -type d -exec chmod g+s {} +` to re-assert the setgid bit
   that `chgrp` clears — the documented step-2 remedy for the 2026-02-12 group-inheritance
   incident. The live tree's managed dirs are currently non-setgid; a real deploy will set the
   setgid bit on all 35. That is the fix landing, not a regression.
   The 35 paths (17 skill dirs + 18 subdirs): `skills/` + {ask-ami, askcode, ask-epics,
   ask-epics/bin, ask-lcls2, ask-nersc, ask-nersc/bin, ask-olcf, ask-olcf/bin, ask-s3df,
   ask-s3df/bin, ask-slac-ai-tools, ask-slac-ai-tools/data, ask-slac-ai-tools/schemas,
   ask-slac-ai-tools/scripts, ask-slurm-s3df, ask-smalldata, ask-tiled, ask-tiled/bin,
   confluence-search, confluence-search/reference, confluence-search/scripts, cuda-docs,
   docs-search, docs-search/bin, docs-search/scripts, elog-search, elog-search/reference,
   elog-search/scripts, experimental-hutch-python, experimental-hutch-python/references,
   experimental-hutch-python/scripts, xpm-seq, xpm-seq/bin, xpm-seq/references} — the exact
   `2755/ps-users` lines in `/tmp/mhr-work/mode-diff.txt`.

2. **2 tree roots: `agents` and `skills`, rehearsal `755 gu` vs live `2750 ps-users`** —
   `rsync_and_chmod()` only touches the per-skill subdirectory, never the roots. In the mock the
   roots were created by hand under `/tmp` (primary group `gu`); in production they already exist
   with their live modes and a deploy does not alter them. Not a real difference in a live run.

3. **15 agent symlinks: mode `777` on both sides, group `gu` (rehearsal) vs `ps-users` (live)** —
   `chgrp -R $GROUP` is applied to `skills/`, not to the `agents/` symlinks, so the symlinks keep
   the creating user's primary group. On Linux a symlink's own mode and group are inert
   (access is resolved through the target), so this is cosmetic. Note the live tree is itself
   mixed on this point (`ask-slac-ai-tools` and `elog-search` are already `gu` live — which is
   why 15, not 17, symlinks appear in this bucket).

**Additionally (not path-counted, filesystem-level):** every live path carries a POSIX ACL
(`user:cwang31:rwx`, `mask::r--`, shown as the trailing `+` in `ls -l`) inherited from the
`/sdf` parent's default ACL. The `/tmp` mock has no ACLs at all. This is an artifact of the
rehearsal location and cannot be reproduced under `/tmp`.

---

## 3. THE CRITICAL BUCKET — the 17 manifest-managed skills, file by file

`SKILL.md` was split into frontmatter and body; the frontmatter was parsed (handling `>`/`>-`
folded scalars and quoted scalars) and compared key-by-key; the body was compared byte-for-byte.
All non-`SKILL.md` files in each skill dir were compared with `cmp`.

| name | SKILL.md identical? | frontmatter differs how? | body identical? | assets identical? | verdict |
|---|---|---|---|---|---|
| ask-ami | NO | live `description: "…"` (double-quoted, verbatim from repo) → rehearsal unquoted plain scalar. Same `name`, same description string. | YES | YES (no assets differ, none missing) | OK — cosmetic reserialization |
| ask-epics | YES (byte-identical) | — | YES | YES | OK — no-op |
| ask-lcls2 | NO | double-quoted → unquoted plain scalar; identical parsed value. | YES | YES | OK — cosmetic reserialization |
| ask-nersc | YES | — | YES | YES | OK — no-op |
| ask-olcf | YES | — | YES | YES | OK — no-op |
| ask-s3df | YES | — | YES | YES | OK — no-op |
| ask-slac-ai-tools | YES | — | YES | YES | OK — no-op |
| ask-slurm-s3df | NO | double-quoted → unquoted plain scalar; identical parsed value. | YES | YES | OK — cosmetic reserialization |
| ask-smalldata | NO | double-quoted → unquoted plain scalar; identical parsed value. | YES | YES | OK — cosmetic reserialization |
| ask-tiled | YES | — | YES | YES | OK — no-op |
| askcode | NO | double-quoted → unquoted plain scalar; identical parsed value. | YES | YES | OK — cosmetic reserialization |
| confluence-search | YES | — | YES | YES | OK — no-op |
| cuda-docs | NO | frontmatter BYTE-IDENTICAL to live | **NO — body changed** | assets: 3 files ADDED (`docs/*.md`, 2.5 MB); no existing asset changed or removed | **FLAGGED — upstream body change (repo HEAD 7da2b2d), not harness-caused** |
| docs-search | YES | — | YES | YES | OK — no-op |
| elog-search | YES | — | YES | YES | OK — no-op |
| experimental-hutch-python | NO | live used a `>` folded multi-line block → rehearsal emits one double-quoted line. Identical parsed value (folding joins lines with single spaces). | YES | YES | OK — cosmetic reserialization |
| xpm-seq | NO | live used a `>-` folded multi-line block → rehearsal emits one double-quoted line. Identical parsed value. | YES | YES | OK — cosmetic reserialization |

Summary: **9/17 byte-identical**, **7/17 frontmatter-only reserialization with a provably equal
parsed `{name, description}`**, **1/17 (`cuda-docs`) with an upstream body change**.
**0/17 with a body change attributable to the manifest-harness work.**

Supporting evidence for the "not harness-caused" claim:
- For all 17, the rehearsed body equals the body of the upstream `claude/skills/<n>/SKILL.md`
  (`body_eq_upstream_claude = True`), and the upstream `opencode/` and `claude/` copies have
  identical bodies (`upstream_oc_body_eq_claude_body = True`) — i.e. reading from
  `claude/skills/<n>` instead of `opencode/skills/<n>` changes nothing.
- For all 8 differing files, the live raw frontmatter is byte-identical to the upstream repo's
  raw frontmatter (`live_raw == upstream_raw = True`), confirming the old path copied frontmatter
  through verbatim and the new path regenerates it from the manifest.

---

## 4. The `claude/` tree — new, and identical to `opencode/`

`/tmp/mhr-mock-deploy/claude/` has no live counterpart at all (the live tree has no `claude/`
directory), so it is 100 % only-in-rehearsal by construction: 75 files / 38 dirs / 0 symlinks,
17 skill dirs, set-equal to the `opencode/` skill dirs.

Verified instead: **for all 17 skills, `claude/skills/<n>/SKILL.md` is byte-identical to
`opencode/skills/<n>/SKILL.md` (17/17).**

Implication: this is the expected result *today* and it is a load-bearing observation, not a bug.
The manifest seeds `harness.description_auto == harness.description_menu` verbatim from each
repo's own frontmatter, so the two rendered sides must come out identical. It confirms
(a) the two-sided render path is wired symmetrically and (b) the description plumbing is a true
no-op at this iteration. It also means **this rehearsal does not exercise the divergence case**:
the moment any entry's `description_auto` differs from its `description_menu`, the two sides will
differ on exactly that line — and that behaviour is *not* proven by this run. The earlier
rehearsal's per-side description check (opencode 17/17 == `description_menu`, claude 17/17 ==
`description_auto`) is the evidence that the two fields are read from the right places; the
byte-identity here is only consistent with it, not independent proof.

---

## 5. Modes and owners — the rule, and what is NOT proven

**Rule.** The mock deploy root lives under `/tmp`: it is not setgid-`ps-data`, and the invoking
user's primary group is `gu`, so anything created by a bare `mkdir` there lands `…:gu`. The live
tree is `cwang31:ps-users` throughout, its two tree roots are `2750` (`drwxr-s---`), and its 17
managed skill dirs are currently **non-setgid `755`**.

**What the rehearsal confirms.** `rsync_and_chmod()`'s intent is `chgrp -R ps-users` → `chmod -R
g+rX` → `find -type d -exec chmod g+s`. The rehearsed tree shows exactly that outcome on
everything the function owns: all 35 managed directories are `2755 cwang31:ps-users`, and all 75
regular files are `cwang31:ps-users` with modes matching live byte-for-byte (`644` for docs/
SKILL.md, `755` for `bin/` executables — zero file-mode differences among the 126 common paths).
The `chgrp`-clears-setgid re-assertion works. Directories deploy.sh does **not** own kept the
mock's `gu`/`755` (`opencode/`, `skills/`, `agents/`), which is correct: the function only
touches per-skill subdirectories.

**What is NOT proven.** `/tmp` cannot reproduce the production situation:
- `$DEPLOY_ROOT` in production is setgid `ps-data` (`drwxrwsr-x psdatmgr ps-data`); `/tmp` is not.
  The `ensure_claude_root()` path that exists specifically to stop the new `claude/` tree from
  inheriting `ps-data` is therefore **untested by this rehearsal** — in the mock there is no
  `ps-data` to inherit. Indeed the mock's `claude/` came out `drwxr-s--- ps-users` rather than the
  `drwxr-xr-x` its `opencode/` sibling has, which is worth resolving before a live run if
  `claude/` is meant to be group- and world-readable like `opencode/`.
- The live tree carries inherited POSIX ACLs (`user:cwang31:rwx`, `mask::r--`); `/tmp` has none,
  so ACL preservation/propagation is untested.
- The rehearsal ran as `cwang31` with primary group `gu`; a deploy run by any other maintainer, or
  under a different umask, is not covered.

**Mode parity between the rehearsed tree and the live tree is therefore NOT proven by this
rehearsal.** What is proven is that `rsync_and_chmod()` produces its documented intent, and that
the only mode deltas it would apply to live are the 35 intended setgid additions.

---

## Appendix — artifacts

- `/tmp/mhr-work/listA.txt`, `/tmp/mhr-work/listB.txt`, `/tmp/mhr-work/listB-nonm.txt`, `/tmp/mhr-work/common.txt`
- `/tmp/mhr-work/content-diff.txt` (8 lines), `/tmp/mhr-work/mode-diff.txt` (52 lines)
- `/tmp/mhr-work/cmp17.py`, `/tmp/mhr-work/cmp17.json` (per-skill machine-readable result)
