# Manifest-side harness metadata: implementation spec

Status: **IMPLEMENTED.** This document began life as a pure specification ("no code
written this iteration") against the working tree of 2026-08-27: `render.sh` 325
lines (UNTRACKED), `deploy.sh` 406 lines (MODIFIED, uncommitted), `migrate.sh` 198
lines (UNTRACKED), `skills.manifest.json` 144 lines (tracked, clean). The code has
since been written. **See "AS BUILT" immediately below for what actually shipped,
and prefer it over the body of this document wherever the two disagree.** Sections
corrected after implementation are marked *as shipped* inline (§A.4, §C1, §D, §F.1).
Companion: `docs/design-single-source-skills.md` (the design this amends),
`docs/cron-script-divergence.md` (the live hazard §F.1 depends on),
`docs/deploy-permissions.md` (§3 setgid trap, §4 the `claude/` root shape).

Every line number in the **body** of this document refers to the file as it stood
*before* implementation. Those numbers are now historical: the files have been
edited and the line numbers have moved. Read them as "here is the place this change
belongs", not as coordinates to apply blindly. The AS BUILT table below has the
current sizes.

---

## AS BUILT

Four files carry this change. Measured, not estimated (`wc -l`, 2026-08-27, branch
`main` at `860ac10`):

| file | lines | git state | what changed |
|---|---|---|---|
| `skills.manifest.json` | 280 | **tracked**, MODIFIED | Every one of the 17 entries gained a `harness` block (`source`, `name`, `kind`, `slug`, `description_auto`, `description_menu`). Nothing else in the file moved: `jq -S 'del(.skills[].harness)'` diffs **empty** against `HEAD`. |
| `deploy.sh` | 572 | **tracked**, MODIFIED | `parse_manifest()` emits a 5th TSV column `has_harness`, computed as `has("harness")` (§C1). New `write_harness_meta()` writes each block to `$META_DIR/<name>.json` under a `trap rm -rf … EXIT INT TERM`. `resolve_harness_source()` replaces `resolve_source_dir()`. `mkdir -p "$AGENTS_DST"` moved inside the non-dry-run branch so a dry run writes nothing. `DEPLOY_CLAUDE` still defaults to `1`. |
| `render.sh` | 429 | **UNTRACKED** | New `--meta <json-file>` flag; the in-repo `skill.json` is demoted from *required* to *fallback*. `fm_end()` / `strip_frontmatter()` remove a leading YAML frontmatter block, wired into **all four** call sites. `kind` defaults to `"skill"` when absent (§D3 note at the call site). |
| `validate-manifest.sh` | 285 | **UNTRACKED**, executable | New. Structural + per-entry checks over the manifest; reports every failure rather than the first. Exits `0` on the real manifest today (with 17 warnings). Exit codes in §D. |
| `docs/design-manifest-harness.md` | 1449 | **UNTRACKED** | This document. |

Two of the four are still untracked and one is uncommitted — see §F.11. Nothing has
been committed and nothing has been pushed.

**Verified properties of the shipped manifest**, by measurement:

```
$ jq '[.skills[] | select(has("harness"))] | length'   skills.manifest.json   # 17
$ jq '[.skills[] | select(has("harness") | not)] | length' skills.manifest.json # 0
$ jq '[.skills[] | select(.harness.description_auto == .harness.description_menu)] | length'
                                                       skills.manifest.json   # 17
```

All 17 carry a block; `description_menu` is byte-identical to `description_auto`
for all 17, so the first deploy is a **no-op on description text** by construction
(§A.4).

**What has NOT been done:** nothing has been deployed to
`/sdf/group/lcls/ds/dm/apps/`; `migrate.sh` is unresolved (§G); the five cron
branches are still unpushed (§F.1); and skill *invocation* has never been tested
end to end — every proof so far is about bytes on disk, not about a harness
loading a skill and running it.

### AS BUILT — iteration 4: the deployment-blocker fixes

A second commit on `feat/manifest-harness-render` (on top of `5e9a05e`) carries the
three blocker fixes. Measured, not estimated (`wc -l`):

| file | lines | delta | what the second commit added |
|---|---|---|---|
| `deploy.sh` | **813** | 572 → 813, **+241** | `assert_cron_group_safe()` — the cron ps-data guard; `is_sha_ref()` plus a SHA-capable clone/update path; a 6th `parse_manifest()` TSV column `cron_script` carrying `.cron.script`; header comment blocks `REF FORMS` and `CRON ps-data GUARD`. `git diff --stat`: **255 insertions, 14 deletions.** |
| `skills.manifest.json` | 280 | ±0 | **one line**: the `cuda-docs` entry's `"ref"` moves from `"main"` to `"421f3df7f1dbc20b4f581aa438eba802e7d3d4f4"`. A normalized `jq -S 'del(.skills[].harness)'` HEAD-vs-worktree diff shows that line and nothing else. `central_data` untouched. |
| `render.sh` | 429 | ±0 | untouched. |
| `validate-manifest.sh` | 285 | ±0 | untouched; still exits `0` on the pinned manifest (17 pre-existing menu-length warnings). |

`bash -n deploy.sh` is clean. `set -euo pipefail` correctness is preserved: every
added command is `if`-guarded, so no unguarded non-zero exit was introduced.

#### The guard — where it sits

`assert_cron_group_safe()` is called from `deploy_skill()` immediately after the
clone/update block and **before source selection** — therefore before
`write_harness_meta()`, `resolve_harness_source()`, `render.sh`, the skill rsync,
the `claude/` rsync, the `agents/` symlink and the `tools/` rsync. Every write to
`$DEPLOY_ROOT` is downstream of it. On refusal it sets `DEPLOY_FAILED=1` and
returns, so sibling skills still deploy and `main()` exits `3` at the end.

It is manifest-driven: it reads only `.cron.script`, which is non-empty for exactly
the five `cron`-bearing entries. The legitimately-`ps-data` paths elsewhere in the
fleet (`data/elog-copilot`, the three elog `tools/` dirs) are unreachable from this
code path.

#### The grep pattern, and why it is scoped this way

```
(^|[;&|(]|[[:space:]])chgrp([[:space:]]+-[^[:space:]]+)*[[:space:]]+['"]?ps-data['"]?([[:space:]]|$)
```

run over `grep -n` output with whole-line shell comments (`^[0-9]+:[[:space:]]*#`)
filtered out first.

Each clause earns its place:

| clause | stops it being too narrow | stops it being too broad |
|---|---|---|
| `(^\|[;&\|(]\|[[:space:]])` before `chgrp` | catches `cd /x && chgrp …`, `foo; chgrp …` | a **filename** containing `chgrp` (`/opt/my-chgrp-ps-data-tool`) is not at a command start |
| `([[:space:]]+-[^[:space:]]+)*` | any option spelling or count: `-R`, `--recursive`, `-h -R` | — |
| `['"]?ps-data['"]?` | `chgrp -R "ps-data"` and `'ps-data'` | — |
| trailing `([[:space:]]\|$)` | — | the group `ps-database` does not match |
| group-**operand position** required | — | `echo "ps-data"`, a log string, `PS_DATA_GROUP=ps-data` do not match |
| comment lines pre-filtered | — | `# we used to chgrp -R ps-data here` is inert documentation; a guard that refuses a deploy over a comment is a guard someone rips out |

Reported line numbers are still the file's own (the `grep -v` runs on `grep -n`
output, so the prefix survives).

**15-case regex unit test, all passing:** 6 positives (the real line plus five
rewordings) and 9 negatives (`ps-users`, `ps-database`, two comment forms,
`echo "ps-data"`, a path containing `chgrp-ps-data`, `chgrp -R "$GROUP"` with a
ps-data comment, `PS_DATA_GROUP=ps-data`, `chgrp -R ps-users "$D" # was ps-data`).

**A second, softer check** covers `chgrp -R "$G"` — a group operand the guard
cannot statically resolve. If `ps-data` also appears anywhere non-commented in that
file it is a **hard error** (fail-closed: the guard cannot prove safety); otherwise
it is a `WARN` and the deploy proceeds, because an unconditional error would
over-fire on any legitimately parameterised script.

**Three more scoping decisions.** A `cron.script` the clone does not contain is an
**error**, not a warning (fail-closed — otherwise one upstream rename silently
disables the check while the `tools/` rsync still ships the bad script). Absolute
and `..`-containing `cron.script` values are rejected, reusing
`resolve_harness_source()`'s containment rules, so a bad manifest value cannot aim
the scan at the already-correct **live** copy and pass. And there is **no override
flag, by design.**

Behaviour, measured: a full 17-entry rehearsal exits `3` with exactly **5**
`DEPLOY REFUSED` blocks (`ask-epics`, `ask-nersc`, `ask-s3df`, `ask-tiled`,
`ask-olcf`), deploys the other **12**, and creates **no `tools/` tree at all**. The
guard keys on **content, not names**: a clone whose cron script was locally
corrected to `ps-users` deploys cleanly at exit `0`, `tools/` included. A
branch-ref, non-cron skill produces a **byte-identical tree** under the old and new
`deploy.sh` (`diff -r` clean, both exit `0`).

#### SHA-ref support

`is_sha_ref()` accepts **full 40-character lowercase hex only**. Anything else —
abbreviated hex, uppercase, a branch, a tag — takes the branch path.

```sh
is_sha_ref() {
  case "$1" in
    *[!0-9a-f]*) return 1 ;;
    ????????????????????????????????????????) return 0 ;;
    *) return 1 ;;
  esac
}
```

Fresh clone on the SHA path: `git init` + `remote add origin` +
`git fetch --depth=1 origin <sha>` + `git checkout -q --detach FETCH_HEAD`
(`git clone --depth=1 -b <sha>` cannot work — `-b` takes a branch or tag name).
Update path: the same fetch + `git checkout -q --force --detach FETCH_HEAD`.

The forced detached checkout is not cosmetic. The old update path did
`checkout "$ref"` then `reset --hard "origin/$ref"` guarded by a `rev-parse
--verify` that a SHA can never satisfy — so on a SHA there was **no reset
equivalent at all**, and a staging clone left attached to a branch by an earlier
run would never be pulled back to the pin. The forced detach fixes both.

Verified on the host (git 2.43.7, GitHub over ssh), not assumed:

- `git fetch --depth=1 origin 524de159dd0777f0c69920f0b03dc51b33dc14d8` — a
  **non-tip** commit — succeeds (`* branch 524de15… -> FETCH_HEAD`, exit 0). So
  `allowAnySHA1InWant` is enabled server-side and shallow SHA fetch is not a
  tip-only special case.
- `git fetch --depth=1 origin 524de15` fails with
  `fatal: couldn't find remote ref 524de15`. Abbreviated SHAs are rejected by the
  protocol regardless, and are anyway indistinguishable from a legal branch name —
  hence the deliberate routing to the branch path, where they fail loudly.

Round-trip tested four ways: fresh clone at the SHA, idempotent re-run, update from
a branch-attached stage to the SHA, and update from a SHA-detached stage back to
`main`. All exit `0` on the expected HEAD.

#### The cuda-docs pin

`"ref": "421f3df7f1dbc20b4f581aa438eba802e7d3d4f4"` — "Initial: cuda-docs knowledge
wrapper", 2026-05-12, exactly **1 commit behind** `main` HEAD `7da2b2d`. The repo
has only 2 commits total, so the search for a content match was exhaustive and
exactly one commit matched: `SKILL.md` md5 `ecf3dfbe1137e04c91bfa80d3f41a04e`,
2541 B, byte-identical to the live deployed file on both the `claude/` and
`opencode/` sides. Rationale, un-pin procedure and its consequences:
`docs/manifest-harness-handoff.md` §9.

---

## 0. Why

Today `render.sh` requires `<source-dir>/skill.json` (line 86) and `deploy.sh`
decides "migrated vs legacy" on the *physical presence* of that file
(`resolve_source_dir()`, lines 178-194). None of the 17 external repos has a
`skill.json`; all 17 carry the old dual `claude/` + `opencode/` trees with
byte-identical `SKILL.md` on both sides (verified by cloning all 17 on 2026-08-27),
and every one of them is laid out uniformly as

```
skill-<name>/
├── claude/skills/<name>/SKILL.md      # native Claude Code frontmatter + assets
├── opencode/skills/<name>/SKILL.md    # byte-identical
├── README.md
└── tools/<x>/                          # 5 repos only
```

where `<name>` is **exactly the manifest `name`** in all 17 cases (measured:
`ask-ami, askcode, ask-epics, ask-lcls2, ask-nersc, ask-olcf, ask-s3df,
ask-slac-ai-tools, ask-slurm-s3df, ask-smalldata, ask-tiled, confluence-search,
cuda-docs, docs-search, elog-search, experimental-hutch-python, xpm-seq`; the
`claude/skills/` and `opencode/skills/` directory name matches the manifest name for
every entry, one skill dir per repo, no exceptions).

Requiring a `skill.json` inside those repos means 17 pull requests against repos
whose content is otherwise correct, and it means each repo's `SKILL.md` has to be
stripped of the frontmatter that makes it a *native, directly-usable* Claude Code
skill. This change moves that metadata into `skills.manifest.json` — the file this
repo already owns — so the skill repos need **no content change at all**.

Precedent for putting harness data in the manifest: the manifest already carries
`central_data`, which `deploy.sh` documents in its header but never reads. A block
that some consumers ignore is schema-consistent here, not novel.

---

## A. The manifest `harness` block

### A.1 Placement

One optional object, `harness`, per element of `.skills[]`. Sibling of `name`,
`repo`, `ref`, `cron`, `central_data`. Nothing else in the manifest changes.

### A.2 Fields

| field | type | required | default | replaces / notes |
|---|---|---|---|---|
| `source` | string | no | `"claude/skills/<manifest .name>"` | **New — has no `skill.json` equivalent.** Repo-relative path of the directory that holds `SKILL.md` and the assets. This is the field that lets the repos keep their existing layout. Must be relative, must not be absolute, must not contain a `..` path segment, no leading `/`, trailing `/` tolerated and stripped. |
| `name` | string | no | manifest `.name` | `skill.json.name`. The harness dispatch name (frontmatter `name:` for skills). Defaulting to the manifest name is right for all 17. |
| `kind` | string | no | `"skill"` | `skill.json.kind`, which was *required* there. Demoted to optional-with-default because 17 of 17 are skills and a default of `"skill"` is never surprising. Must be `"skill"` or `"command"` when present. |
| `slug` | string | no | `harness.name`, i.e. transitively the manifest `.name` | `skill.json.slug`. On-disk directory / filename inside the **rendered** tree. Note `deploy.sh` still keys the *deployed* destination on the manifest `name`, not on `slug` (lines 284, 295, 306, 313) — unchanged. |
| `description_auto` | string | **yes** | — | `skill.json.description_auto`. Claude-side `description:`. Must be non-empty. |
| `description_menu` | string | **yes** | — | `skill.json.description_menu`. opencode-side `description:`. Must be non-empty. |
| `argument_hint` | string | no | absent | `skill.json.argument_hint`. Emitted as `argument-hint:` for `kind=command` only. |
| `user_invocable` | boolean | no | `false` | `skill.json.user_invocable`. Emitted as `user-invocable: true` for `kind=command` only. Any value other than JSON `true` means absent. |

Deliberately **not** added, unchanged from `docs/design-single-source-skills.md` §4:
`allowed-tools`, `model`, an explicit `assets` list. `cron` and `central_data` keep
their existing top-level homes and are *not* duplicated into `harness`.

### A.3 Multi-skill repos

**Decision: one manifest entry per deployed skill.** A repo carrying two skills gets
two `.skills[]` entries with the same `repo`/`ref` and different `name` +
`harness.source`:

```json
{ "name": "thing-a", "repo": "org/skill-things", "ref": "main",
  "harness": { "source": "claude/skills/thing-a", ... } },
{ "name": "thing-b", "repo": "org/skill-things", "ref": "main",
  "harness": { "source": "claude/skills/thing-b", ... } }
```

Rejected alternative: `harness` as an **array** of blocks. Rejected because every
deploy destination in `deploy.sh` is keyed on the manifest `name`
(`$SKILLS_DST/$name/`, `$AGENTS_DST/$name`, `$CLAUDE_SKILLS_DST/$name/`,
`$CLAUDE_CMDS_DST/$name.md`), and an array would force the invention of a
per-element destination name — which is precisely what `name` already is. It would
also break `./deploy.sh <name>` selection (lines 368-378) and the
"requested skill not in manifest" warning (lines 380-394).

Accepted cost: two entries with the same repo clone twice, into
`$STAGING_ROOT/thing-a` and `$STAGING_ROOT/thing-b` (line 201 keys staging on
`name`). None of the 17 is affected. Re-keying staging on the repo slug is a
separate, optional optimisation and is **out of scope**.

### A.4 Complete example entry

```json
    {
      "name": "ask-s3df",
      "repo": "carbonscott/skill-ask-s3df",
      "ref": "main",
      "cron": {
        "schedule": "0 * * * *",
        "script": "tools/sdf-docs/scripts/sdf-docs-cron.sh",
        "host": "sdfcron001"
      },
      "central_data": "/sdf/group/lcls/ds/dm/apps/dev/data/sdf-docs",
      "harness": {
        "source": "claude/skills/ask-s3df",
        "name": "ask-s3df",
        "kind": "skill",
        "slug": "ask-s3df",
        "description_auto": "S3DF documentation assistant. Use when users ask about S3DF accounts, access, Slurm, storage, data transfer, conda, Jupyter, MPI, containers, or any SLAC Shared Scientific Data Facility topic.",
        "description_menu": "S3DF documentation assistant. Use when users ask about S3DF accounts, access, Slurm, storage, data transfer, conda, Jupyter, MPI, containers, or any SLAC Shared Scientific Data Facility topic."
      }
    }
```

**`description_menu` is byte-identical to `description_auto` here, and that is
what shipped for all 17 entries.** An earlier draft of this section showed a
hand-shortened menu label ("S3DF documentation assistant.") and that was
misleading: it implied the seeding step made an editorial judgement it did not
make. Both fields were seeded **verbatim** from each repo's own frontmatter
`description`, which makes the first deploy a provable no-op on description text
— the only property worth having on day one. Shortening `description_menu` into a
real @-menu label is a **deliberate later human decision**, one repo at a time,
not an oversight and not something to automate; the validator already flags every
over-120-char menu string as a `WARN` so the backlog is self-listing. Until
someone does that work, the @-menu shows the long text.

(`source`, `name`, `kind` and `slug` above are all equal to their defaults for this
entry and could be omitted. Write them out anyway for the 17 — an explicit
`source` is the one field a reader needs in order to know which of the repo's two
duplicated trees is being used, and leaving it implicit is how the §F.5 risk bites.)

---

## B. `render.sh` changes

### B1. How metadata arrives — interface

**DECISION: a single `--meta <json-file>` flag carrying one JSON object with the
same field names as the `harness` block.**

Options compared:

| option | verdict |
|---|---|
| `--meta <json-file>` | **CHOSEN.** `deploy.sh` already has `jq`, so producing the file is one `jq` call and one redirect. `render.sh` already parses JSON with `jq` (lines 92-101), so the parse block changes only its *input path* — seven `jq -r` calls keep their exact shape. Descriptions are long, trigger-dense prose containing commas, slashes, parentheses, em dashes and (in `ask-slurm-s3df`, `askcode`, `ask-ami`, `ask-lcls2`, `ask-smalldata`, `confluence-search`) embedded double quotes; a file never puts any of that through an `argv` round-trip or a shell re-split. The file is also inspectable after a failed deploy, which is worth a lot when the failure mode is "wrong description shipped to 17 skills". |
| individual `--name/--kind/--slug/--desc-auto/--desc-menu/--argument-hint/--user-invocable` flags | Rejected. Seven new arms in the `while` loop at lines 58-68, each with a `--flag=value` twin (the existing parser supports both forms for `--target`, lines 60-61, and inconsistency there is a trap). Every caller must then re-quote the descriptions correctly, and `deploy.sh` would have to build an array with `mapfile`/`readarray` or a `jq -r ... | while read` loop — reintroducing exactly the quoting fragility the JSON file avoids. Marginally nicer for a human typing one invocation by hand; the fixture in §E shows a `--meta` file is a 6-line heredoc, so that advantage is small. |
| environment variables (`SKILL_NAME=`, `SKILL_DESC_AUTO=`, …) | Rejected. Invisible in the command line, so a `set -x` trace or a `ps` snapshot of a hung deploy does not show what was rendered. They also *leak across invocations*: `deploy.sh` calls `render.sh` in a loop from one shell, and one un-cleared variable silently contaminates the next skill — a fleet-wide description swap with no error. The existing `DRY_RUN` env var is precedent for a *boolean mode switch*, not for payload data. |

**In-repo `skill.json`: no longer required, still supported as a fallback.**

- When `--meta <file>` is given: `<file>` is the sole source of metadata.
  `$SRC/skill.json` is **not read even if present**. No merging of the two — merging
  creates two homes for one fact, which is the exact failure the parent design
  (`docs/design-single-source-skills.md` §1a) exists to remove.
- When `--meta` is absent and `$SRC/skill.json` exists: current behaviour, byte for
  byte.
- When neither: usage error, exit 1.

Why keep the fallback rather than delete it: `render.sh` is also the tool used by
hand for the `deploy-opencode` repo's own `src/<slug>/` shape (design doc §3), is
the tool `migrate.sh` output is checked with (design doc §7 step 5), and is the only
drift check available via `--check`. Deleting the `skill.json` path would break
those callers for no benefit — the requirement is only that it stop being
*mandatory*. It costs one `if/else` around lines 95-101.

### B1.1 Exact edits

**Line 86**, delete:

```bash
[ -f "$SRC/skill.json" ] || { echo "ERROR: $SRC/skill.json not found" >&2; exit 1; }
```

**Lines 58-68**, add two arms to the parser, both forms, matching the `--target`
style already there:

```bash
    --meta) META="${2:-}"; shift 2 ;;
    --meta=*) META="${1#*=}"; shift ;;
```

**Line 29-30 area**, initialise alongside `CHECK` / `TARGETS`:

```bash
META=""
```

**Lines 90-110**, replace the whole "skill.json parse + validation" block with a
metadata-source selection followed by the *same* seven reads against a resolved
`$META_SRC`:

```bash
# ─── Metadata: --meta file, else in-repo skill.json ───────────────────────
# Absent fields read back as the empty string.
META_SRC=""
if [ -n "$META" ]; then
  [ -f "$META" ] || { echo "ERROR: --meta file not found: $META" >&2; exit 1; }
  META_SRC="$META"
elif [ -f "$SRC/skill.json" ]; then
  META_SRC="$SRC/skill.json"
else
  echo "ERROR: no metadata: pass --meta <json-file>, or provide $SRC/skill.json" >&2
  exit 1
fi

jq -e . "$META_SRC" >/dev/null 2>&1 || {
  echo "ERROR: $META_SRC is not valid JSON" >&2; exit 1; }

NAME="$(jq -r '.name // ""' "$META_SRC")"
KIND="$(jq -r '.kind // "skill"' "$META_SRC")"
SLUG="$(jq -r '.slug // .name // ""' "$META_SRC")"
DESC_AUTO="$(jq -r '.description_auto // ""' "$META_SRC")"
DESC_MENU="$(jq -r '.description_menu // ""' "$META_SRC")"
ARGHINT="$(jq -r '.argument_hint // ""' "$META_SRC")"
USERINV="$(jq -r 'if .user_invocable == true then "true" else "" end' "$META_SRC")"

[ -n "$NAME" ] || { echo "ERROR: $META_SRC: 'name' is required" >&2; exit 1; }
[ -n "$SLUG" ] || SLUG="$NAME"
[ -n "$DESC_AUTO" ] || { echo "ERROR: $META_SRC: 'description_auto' is required" >&2; exit 1; }
[ -n "$DESC_MENU" ] || { echo "ERROR: $META_SRC: 'description_menu' is required" >&2; exit 1; }
case "$KIND" in
  skill|command) ;;
  *) echo "ERROR: $META_SRC: 'kind' must be \"skill\" or \"command\" (got '$KIND')" >&2; exit 1 ;;
esac
```

Two behaviour deltas inside that block, both intentional:

1. `KIND` now defaults to `"skill"` (was `.kind // ""`, line 96, which then failed
   the `case` at 107-110 when absent). This matches §A.2. An in-repo `skill.json`
   that omits `kind` therefore stops being an error — acceptable, and no existing
   `skill.json` in the wild omits it (there are none in the wild at all).
2. Every error message now names `$META_SRC` instead of the literal string
   `skill.json:`, so the operator sees which file was actually parsed.

Note the `.name` fallback inside `.slug // .name // ""` still works when `--meta`
supplies a `name`; `deploy.sh` normalises the block before writing it (§C1) so in
the deploy path all four of `source`/`name`/`kind`/`slug` are always present
explicitly and no defaulting is exercised twice.

### B2. Frontmatter stripping

A native Claude Code `SKILL.md` **always** has frontmatter. `render.sh` must emit
exactly one block, carrying the deployer's description, so the source block has to
go.

#### Contract

- **A leading frontmatter block exists** iff line 1, after stripping an optional
  UTF-8 BOM and an optional trailing CR, is exactly `---`.
- **It ends** at the first *subsequent* line that, after stripping an optional
  trailing CR, is exactly `---` or exactly `...` (YAML permits `...` as a document
  terminator).
- **No frontmatter** (line 1 is anything else, including a blank line, including a
  file that begins with blank lines and *then* has `---`): the file passes through
  **byte-for-byte unchanged**. A leading blank line is not skipped in the search —
  line 1 must be `---` or there is no block. This is deliberate: it makes the rule
  trivially auditable and it is what the Claude Code loader itself does.
- **Unterminated opening `---`** (line 1 is `---` and no later line is `---`/`...`):
  the file passes through **unchanged**, and a `WARN:` line goes to **stderr**. It
  must never eat the whole file. Rationale: silently emitting an empty body would
  deploy an empty skill, and `set -euo pipefail` would not catch it because nothing
  fails; a hard `exit 1` was considered and rejected because a single malformed repo
  would then abort a fleet deploy that is otherwise fine — the WARN plus a
  correct-but-unstripped body is the loud-and-safe middle. (The resulting file will
  have two frontmatter blocks and the §D/§E proof will catch it.)
- **A `---` horizontal rule later in the body survives**, because scanning stops at
  the closing marker of the leading block and everything from there on is copied
  verbatim. Proven by the §E fixture.
- **After the closing marker, at most one blank line is consumed.** `render.sh`'s
  `emit_frontmatter` already prints `---\n\n` (line 205), so consuming exactly one
  blank line reproduces the byte-for-byte round trip documented in the design doc
  §3 ("Body boundary, exactly"). If the line after the closing marker is not blank,
  nothing is consumed.
- **CRLF**: line endings are only normalised *for the purpose of matching* the
  markers. The emitted body keeps whatever line endings it had. No CRLF-to-LF
  rewrite — that would be a content change outside this iteration's scope.
- **BOM**: only considered when testing line 1 for `---`. If there is no leading
  block, the BOM survives into the output (pass-through unchanged). If there *is* a
  leading block, the BOM was inside the stripped region and is gone, which is
  correct.
- **Empty file / one-line file**: `end=0`, pass-through.

#### Implementation

Add after `has_assets()` (i.e. after current line 154), before the
"YAML scalar emission" banner:

```bash
# ─── Frontmatter stripping ────────────────────────────────────────────────
# A native Claude Code SKILL.md carries its own YAML frontmatter. render.sh
# emits exactly ONE block, built from the DEPLOYER's metadata, so a leading
# block in the source must be removed first.
#
# Leading block  = line 1 is exactly '---' (after an optional UTF-8 BOM and an
#                  optional trailing CR).
# Ends at        = the first LATER line that is exactly '---' or '...'.
# No block       = pass the file through byte-for-byte.
# Unterminated   = pass the file through byte-for-byte and WARN. Never eat the
#                  file: an empty body deploys an empty skill and nothing fails.
# A '---' horizontal rule later in the body is untouched: scanning stops at the
# closing marker and the rest is copied verbatim.
# Exactly one blank line after the closing marker is consumed, because
# emit_frontmatter already prints '---\n\n'. See docs/design-manifest-harness.md B2.
#
# fm_end <file> -> line number of the closing marker, or 0 if there is no
# terminated leading block. NOTE: awk's `exit` runs the END block, hence the
# `done` guard — without it END prints a second number.
fm_end() {
  awk '
    NR == 1 {
      l = $0
      sub(/^\357\273\277/, "", l)   # UTF-8 BOM, octal (portable; \x is gawk-only)
      sub(/\r$/, "", l)
      if (l != "---") { done = 1; print 0; exit }
      next
    }
    {
      l = $0
      sub(/\r$/, "", l)
      if (l == "---" || l == "...") { done = 1; print NR; exit }
    }
    END { if (!done) print 0 }
  ' "$1"
}

# strip_frontmatter <file> -> body on stdout
strip_frontmatter() {
  local f="$1" end first
  end="$(fm_end "$f")"
  if [ "$end" -gt 0 ]; then
    # Everything after the closing marker, minus at most one leading blank line.
    sed -n "$((end + 1)),\$p" "$f" \
      | awk 'NR == 1 { l = $0; sub(/\r$/, "", l); if (l == "") next } { print }'
    return 0
  fi
  first="$(head -n 1 "$f" | sed -e 's/^\xEF\xBB\xBF//' -e 's/\r$//')"
  if [ "$first" = "---" ]; then
    echo "  WARN: $f opens with '---' but the frontmatter block is never closed;" >&2
    echo "        passing the body through unstripped. The rendered file will" >&2
    echo "        carry TWO frontmatter blocks — fix the source." >&2
  fi
  cat "$f"
}
```

Notes for the implementer:

- `fm_end` emits exactly one integer on stdout in every case, including an empty
  file (`END` fires with `done` unset → `0`).
- `sed -n "$((end + 1)),\$p"` prints nothing when `end` is the last line — correct,
  an empty body.
- The `\xEF\xBB\xBF` escape in the `sed` line is GNU sed and the deploy host is
  Linux/GNU. The `awk` BOM match uses **octal** `\357\273\277` because `\x` escapes
  are a gawk extension and `awk` here may be mawk.
- Bash 4.4.20: no `${var@Q}`, no `mapfile -d`, nothing newer than 4.2 is used.
  `local f="$1" end first` on one line is fine in 4.4.
- Under `set -euo pipefail`: `strip_frontmatter` is always used at the *head* of a
  `{ …; } > file` group, never as the left side of a pipe whose right side may exit
  early, so `pipefail` cannot bite. `head -n 1` closing the pipe early on a large
  file is inside a command substitution (SIGPIPE to `sed`, not to the caller) and is
  the last statement before `cat`, so its status is discarded by the `if`.

#### Call sites that change — all four

| line | current | becomes |
|---|---|---|
| 221 | `{ emit_frontmatter "$target"; cat "$SRC/SKILL.md"; } > "$tmp/rendered.md"` | `{ emit_frontmatter "$target"; strip_frontmatter "$SRC/SKILL.md"; } > "$tmp/rendered.md"` |
| 236 | `{ emit_frontmatter "$target"; cat "$SRC/SKILL.md"; } > "$tmp/SKILL.md"` | `… strip_frontmatter …` |
| 284 | `{ emit_frontmatter "$target"; cat "$SRC/SKILL.md"; } > "$dest"` | `… strip_frontmatter …` |
| 291 | `{ emit_frontmatter "$target"; cat "$SRC/SKILL.md"; } > "$stage/SKILL.md"` | `… strip_frontmatter …` |

Nothing else in the file reads `$SRC/SKILL.md`. Line 87
(`[ -f "$SRC/SKILL.md" ] || …`) stays exactly as it is — `SKILL.md` remains
required.

### B3. The `skill.json` exclusion sites

**Line 138, `ASSET_EXCLUDES`.** Keep `--exclude='skill.json'` verbatim. An rsync
exclude pattern that matches nothing is a **no-op** — rsync does not warn, does not
error, and does not change its exit status for an unused filter rule. Removing it
would be a regression for the `skill.json`-fallback callers (§B1) and for the
`deploy-opencode` `src/<slug>/` shape, where the file *does* exist and must not
ship. Leave it.

**Line 148, `has_assets()`'s `case`.** Same: keep `skill.json` in the skip list.
The loop only ever tests basenames of files that exist (`[ -e "$f" ] || continue`,
line 146), so a pattern for an absent file is never reached and costs nothing.

**One real consequence of the new `source` field**, which the implementer must not
miss: with `source: "claude/skills/<name>"`, `$SRC` is a *skill directory inside the
repo*, not the repo root. Therefore

- the anchored excludes `/claude/`, `/opencode/`, `/.rendered/` (line 140) now
  anchor at the skill directory and match nothing there. They stay — they are still
  correct for the repo-root and `src/<slug>/` shapes, and they are what makes
  in-place rendering idempotent (design doc §5).
- `tools/` (line 139, unanchored) still matches anything named `tools/` at any depth
  under `$SRC`. No current skill dir has one. If one ever does, its `tools/` is
  silently dropped from the assets — see §F.6.
- the repo-root `README.md` **stops shipping** into the rendered trees, because it
  is now outside `$SRC`. This is a change from what the design doc §5 predicted for
  the single-source layout, and it is an improvement, but it *is* a content change
  to the deployed tree for repos whose current `claude/skills/<name>/` contains no
  README. Diff the asset sets before and after (§F.6).

### B4. Everything else the change touches

**Header comment + `usage()` (lines 2-24 and 32-55).** `usage()` sed-prints the
header comment (`sed -n '2,24p' "$0"`, line 33), so the two move together. Rewrite
lines 2-24 to describe the new interface and **update the sed line range in `usage()`
to whatever the new header's last line is.** Getting that range wrong is silent — it
truncates or over-prints the help text — so the implementer must re-check it after
editing. Proposed new header (25 lines, so the range becomes `'2,25p'`):

```
# Render one skill into per-harness trees.
#
# Metadata comes from --meta <json-file> (the deployer's harness block), or,
# when --meta is absent, from <source-dir>/skill.json. The source SKILL.md may
# carry its own YAML frontmatter; a LEADING block is stripped and replaced with
# exactly one block built from the metadata above.
#
# Writes, under <output-dir>:
#
#   kind=skill    <out>/claude/skills/<slug>/SKILL.md   + assets
#                 <out>/opencode/skills/<slug>/SKILL.md + assets
#                 <out>/opencode/agents/<slug> -> ../skills/<slug>
#   kind=command  <out>/claude/commands/<slug>.md
#                 <out>/opencode/commands/<slug>.md     (no agents/ symlink)
#
# Assets = everything else in the source dir, EXCEPT skill.json, SKILL.md,
# .git/, tools/ (harness-neutral; deploy.sh ships it separately) and the
# build-output dirs /claude/, /opencode/ and /.rendered/ at the source root.
#
# Usage:
#   ./render.sh [--meta <json>] <source-dir> <output-dir>
#   ./render.sh --target claude   [--meta <json>] <source-dir> <output-dir>
#   DRY_RUN=1 ./render.sh <source-dir> <output-dir>
#   ./render.sh [--meta <json>] --check <source-dir> <tree-to-compare>
#
# bash + jq only, matching deploy.sh. See docs/design-manifest-harness.md.
```

Add to the `Options:` heredoc (lines 34-54), directly above `--target`:

```
  --meta <json-file>               Harness metadata (name/kind/slug/
                                   description_auto/description_menu/
                                   argument_hint/user_invocable). Overrides
                                   <source-dir>/skill.json entirely; the two
                                   are never merged. Without it, skill.json is
                                   required as before.
```

**Validation error messages.** Covered in §B1.1 — every `skill.json:` prefix becomes
`$META_SRC:`.

**`--check` mode (`check_target`, lines 214-249).** Two changes only: the two `cat`
call sites at 221 and 236 become `strip_frontmatter` (§B2), and `--check` now
accepts `--meta`, which it gets for free from the shared parser. Semantics are
unchanged and important: `render.sh --meta <manifest-derived.json> --check
--target opencode <stage>/claude/skills/<name> /sdf/group/lcls/ds/dm/apps/dev`
compares the *would-be* render against the **live deployed tree**. That is the
pre-flight gate §F.3 depends on, and it works with zero further code.

**`mktemp` templates (lines 218, 289)** use `$SLUG`, which is now manifest-supplied.
`mktemp -d "…/check-$SLUG-XXXXXX"` breaks if `$SLUG` ever contains a `/`. The
validator (§D) rejects a `slug` containing `/`; no code change needed in
`render.sh`, but note the dependency.

**Line 318/320** print `kind=$KIND, name=$NAME` — unchanged, and now reflects the
deployer's values, which is exactly what an operator wants to see in the log.

---

## C. `deploy.sh` changes

### C1. Getting the harness block into `deploy_skill()`

A JSON object cannot ride a `@tsv` row. **Mechanism: `parse_manifest()` gains one
boolean column; the block itself travels as a per-skill temp file written by a `jq`
lookup, and that same file is what `render.sh --meta` reads.** One producer, one
consumer, one file, no re-quoting anywhere.

**Lines 71-73**, replace:

```bash
# ─── Manifest parse via jq ────────────────────────────────────────────────
# Emits one TSV row per skill: name<TAB>repo<TAB>ref<TAB>has_cron(0|1)<TAB>has_harness(0|1)
parse_manifest() {
  jq -r '.skills[]
         | [ .name, .repo, (.ref // "main"),
             (if .cron then 1 else 0 end),
             (if has("harness") then 1 else 0 end) ]
         | @tsv' "$MANIFEST"
}
```

**The test is KEY PRESENCE, `has("harness")` — not `(.harness | type) == "object"`.
This distinction is load-bearing; do not "simplify" it back.**

An earlier draft of this spec used the type test. It is wrong, and it reopens
exactly the hole §F.9 exists to close. Trace an entry whose `harness` key is
present but malformed — a string, an array, an explicit `null`, or an object
nested one level too deep after a bad edit:

| predicate | malformed block scores | branch taken | deploy exit |
|---|---|---|---|
| `(.harness \| type) == "object"` | `0` | **legacy** | **0 — silent success** |
| `has("harness")` | `1` | harness | non-zero — hard error |

Under the type test the operator's broken metadata is not reported at all. The
skill still deploys, from the legacy tree, with the repo's own frontmatter, and
`deploy.sh` exits 0 — so nothing in CI, in a log, or on the terminal says the
manifest entry they just wrote was ignored. That is the "typo'd `harness` key
silently reverts to the legacy path" failure mode, and it is the single worst
outcome available here, because it is indistinguishable from success.

Key presence gets it right by construction: a present-but-malformed block scores
`1`, reaches `write_harness_meta()`, and fails loudly there. Only a **fully
absent** `harness` key means legacy — which is the only thing "legacy" should
ever mean. The type test conflates "the author did not opt in" with "the author
opted in and got it wrong"; those two need opposite handling.

`has` would error on a non-object input, but `.skills[]` elements are objects by
the time this filter runs, and the validator (§D) rejects a manifest where they
are not.

**As shipped**, `deploy.sh` `parse_manifest()` carries this predicate together
with a comment recording the same reasoning, so the rationale survives at the
call site and not only here.

**Line 368** and **line 377**, widen the reader and the call:

```bash
  while IFS=$'\t' read -r name repo ref has_cron has_harness; do
    …
    deploy_skill "$name" "$repo" "$ref" "$has_harness"
```

**Temp dir, created once.** Insert immediately after line 67 (`mkdir -p
"$STAGING_ROOT"`), at top level so the `trap` is installed before anything can
fail:

```bash
# ─── Harness metadata temp files ──────────────────────────────────────────
# One normalised JSON object per skill, handed to render.sh via --meta. Kept in
# a single run-scoped dir so one trap cleans them all up, including on the
# `exit 3` path at the end of main() and on Ctrl-C. Under `set -euo pipefail` a
# failing mktemp aborts here, before any deploy work starts, which is what we
# want: no metadata dir, no deploy.
META_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deploy-harness-$USER-XXXXXX")"
trap 'rm -rf "$META_DIR"' EXIT INT TERM
```

`META_DIR` is assigned before the `trap` references it, so `set -u` is satisfied.
`rm -rf` on a `mktemp -d` result is unconditional and safe; the variable is never
empty because `set -e` would have aborted on a failed `mktemp`.

**Writing one skill's meta file**, inside `deploy_skill()` (see §C2 for where):

```bash
  local meta="$META_DIR/$name.json"
  # jq -e exits 4 when the filter produces nothing, which under `set -e` would
  # abort the whole deploy. Wrapping it in `if` suspends errexit for the
  # condition, so an entry with no harness block is a value, not a fatality.
  if jq -e --arg n "$name" '
        .skills[] | select(.name == $n) | .harness
        | select(type == "object")
        | { source:           ((.source // ("claude/skills/" + $n)) | sub("/+$"; "")),
            name:             (.name // $n),
            kind:             (.kind // "skill"),
            slug:             (.slug // .name // $n),
            description_auto: (.description_auto // ""),
            description_menu: (.description_menu // "") }
          + (if (.argument_hint // "") != "" then {argument_hint: .argument_hint} else {} end)
          + (if .user_invocable == true then {user_invocable: true} else {} end)
      ' "$MANIFEST" > "$meta"
  then
    :
  else
    rm -f "$meta"
    echo "  ERROR: $name declares a 'harness' block that is not a usable object" >&2
    DEPLOY_FAILED=1
    return 0
  fi
```

Three things the implementer must preserve:

- The block is **normalised here, once**. Every downstream reader — `deploy.sh`'s
  own `kind`/`slug` reads and `render.sh` — then sees all six mandatory keys
  present, and no defaulting logic exists in two places.
- `sub("/+$"; "")` strips a trailing slash from `source`. jq 1.6 has `sub`.
- The `if … then : else … fi` form is load-bearing under `set -e`. Do not
  "simplify" it to `jq … > "$meta" || { … }` without checking; that form is also
  errexit-safe, but the `-e` exit code 4 vs 5 distinction is easier to reason about
  in the `if`.

Note `$name.json` is a safe filename because the validator (§D) rejects a `name`
containing `/`, and `$STAGING_ROOT/$name` (line 201) already depends on the same
property today.

### C2. Replacing `resolve_source_dir()`

**Delete lines 165-194 entirely** (the banner comment and the function). Replace
with a manifest-side resolver:

```bash
# ─── Source-shape resolution ──────────────────────────────────────────────
# Manifest-side, not filesystem-side. A manifest entry with a 'harness' block is
# single-source: harness.source names the directory INSIDE the clone that holds
# SKILL.md and the assets, defaulting to claude/skills/<name>. The repo needs no
# skill.json and no content change of any kind.
#
# An entry with NO harness block takes the legacy path unchanged (see below).
#
# resolve_harness_source <stage> <meta-file> -> prints the absolute source dir,
# returns 1 (having printed an ERROR) if it is unusable.
resolve_harness_source() {
  local stage="$1"
  local meta="$2"
  local rel dir

  rel="$(jq -r '.source' "$meta")"

  case "$rel" in
    /*)      echo "  ERROR: harness.source must be repo-relative, got '$rel'" >&2; return 1 ;;
    ..|../*|*/../*|*/..)
             echo "  ERROR: harness.source must not contain '..', got '$rel'" >&2; return 1 ;;
    ""|null) echo "  ERROR: harness.source is empty" >&2; return 1 ;;
  esac

  dir="$stage/$rel"
  [ -d "$dir" ] || {
    echo "  ERROR: harness.source '$rel' is not a directory in this repo" >&2; return 1; }
  [ -f "$dir/SKILL.md" ] || {
    echo "  ERROR: harness.source '$rel' has no SKILL.md" >&2; return 1; }
  echo "$dir"
}
```

### C2.1 Entries WITHOUT a harness block

**DECISION: keep the legacy branch (current line 266), unchanged, but print a
`DEPRECATED:` line. Do not make a missing `harness` block an error in `deploy.sh`.
Enforcement of "all 17 carry one" belongs to the validator (§D), run as a
pre-flight gate, not to the deployer.**

Reasons, in the order that decided it:

1. `deploy.sh` and `skills.manifest.json` are separate files with separate change
   cadences, and the manifest is the tracked one. A hotfix that adds an 18th repo,
   or a `git checkout` of an older manifest during a rollback, would — under an
   error policy — take the *entire* deploy to exit 3, including the 17 entries that
   are perfectly configured. That converts a partial-configuration problem into a
   total outage of the deploy path.
2. The legacy branch is the **rollback path** for this whole campaign. If the
   rendered output turns out wrong in production, the fix is to delete the `harness`
   blocks from the manifest and re-deploy, getting byte-identical output to today.
   That rollback is only available if the legacy branch still works.
3. It costs one `elif` that already exists.

**But**: a `harness` key that is *present and malformed* is a hard error
(`DEPLOY_FAILED=1`, per §C1). Only a **fully absent** `harness` key takes the legacy
path. That closes the "typo'd key silently reverts to legacy" hole, which is the one
real argument for the error policy.

### C3. Rewriting lines 219-276

Replace the whole block (current 219-276) with:

```bash
  # ─── Source selection: manifest harness block vs legacy checked-in tree ──
  # An entry with a 'harness' block is single-source: render from
  # <stage>/<harness.source>, deploy the renders to both harness trees. An entry
  # without one is pre-migration and takes the original path: opencode only,
  # from the repo's checked-in opencode/skills/<name>/, nothing to the claude
  # tree. The two coexist so the manifest can move one entry at a time, and so
  # the campaign has a rollback (docs/design-manifest-harness.md C2.1).
  local src=""
  local claude_src=""
  local claude_cmd=""
  local kind="skill"
  local srcdir=""
  local meta=""

  if [ "$has_harness" = "1" ]; then
    meta="$META_DIR/$name.json"
    #  … the `if jq -e … ` normalisation block from §C1 goes here …
    srcdir="$(resolve_harness_source "$stage" "$meta")" || {
      DEPLOY_FAILED=1
      return 0
    }
  fi

  if [ -n "$srcdir" ]; then
    local slug rtarget
    kind="$(jq -r '.kind' "$meta")"
    slug="$(jq -r '.slug' "$meta")"
    if [ ! -x "$RENDER" ]; then
      echo "  WARN: $RENDER missing or not executable; cannot render $name" >&2
      return 0
    fi
    echo "  source dir: ${srcdir#$stage/} (from manifest harness.source)"
    if [ "$DEPLOY_CLAUDE" = "1" ]; then rtarget="both"; else rtarget="opencode"; fi
    # DRY_RUN=0 on purpose. DRY_RUN protects $DEPLOY_ROOT, not the staging dir.
    rm -rf "$stage/.rendered"
    DRY_RUN=0 "$RENDER" --meta "$meta" --target "$rtarget" \
      "$srcdir" "$stage/.rendered" | sed 's/^/  /'
    echo "  ✓ rendered from manifest harness block (kind=$kind, slug=$slug, target=$rtarget)"
    [ "$slug" = "$name" ] || \
      echo "  NOTE: harness slug '$slug' differs from manifest name '$name'"
    if [ "$kind" = "command" ]; then
      [ "$DEPLOY_CLAUDE" = "1" ] && claude_cmd="$stage/.rendered/claude/commands/$slug.md"
      echo "  NOTE: kind=command — claude/commands only; opencode/commands is not"
      echo "        a deploy destination (design doc §6)"
    else
      src="$stage/.rendered/opencode/skills/$slug/"
      [ "$DEPLOY_CLAUDE" = "1" ] && claude_src="$stage/.rendered/claude/skills/$slug/"
    fi
  elif [ -d "$stage/opencode/skills/$name" ]; then
    echo "  DEPRECATED: no 'harness' block in the manifest for '$name'; using the" >&2
    echo "              checked-in opencode/skills/$name/. Add a harness block —" >&2
    echo "              see docs/design-manifest-harness.md §A." >&2
    src="$stage/opencode/skills/$name/"
  else
    echo "  ERROR: $repo matches neither shape:" >&2
    echo "         no 'harness' block in the manifest entry for '$name', and no" >&2
    echo "         opencode/skills/$name/ directory in the repo. Nothing deployed." >&2
    DEPLOY_FAILED=1
    return 0
  fi
```

Specifically, keyed to the current numbering:

- **lines 234-235** (`kind=$(jq …"$srcdir/skill.json")`, `slug=$(jq …)`) become
  reads of `"$meta"` with **no `//` defaults**, because §C1 normalised them. Delete
  line 236 (`[ -n "$slug" ] || slug="$name"`) — it is dead once normalisation runs.
- **line 241** (`[ "$srcdir" = "$stage" ] || echo "  source dir: …"`) becomes an
  unconditional `echo` of the relative source, since under the new design the source
  dir is *never* the repo root for the 17 and the operator always wants to see which
  of the repo's two trees was used. That is a §F.5 mitigation, not cosmetics.
- **lines 271-275** (the neither-shape error) keep their structure; only the message
  changes, from "no skill.json at repo root or src/$name/" to "no 'harness' block in
  the manifest entry". Keep `DEPLOY_FAILED=1` and `return 0`; keep `exit 3` at line
  402.
- **line 197** (`deploy_skill()`) gains a fourth positional:
  `local has_harness="$4"`.
- **Header comment, lines 5-12**, is now wrong (it describes `skill.json` at the
  root or `src/<name>/`). Rewrite to describe the `harness` block, the `source`
  field and its `claude/skills/<name>` default. `deploy.sh` has no
  `usage()`-prints-the-header trick, so the header is prose only and no `sed` range
  has to move.

### C4. The `AGENTS_DST` defect

`AGENTS_DST` (`$DEPLOY_ROOT/opencode/agents`, line 29) is referenced only at line
313 (`local agent_link="$AGENTS_DST/$name"`) and is never `mkdir`'d. On a virgin
deploy root, `ln -s "../skills/$name" "$agent_link"` at line 318 fails with
`No such file or directory`; under `set -euo pipefail` that aborts the whole run
mid-skill.

**Fix: one line, inserted as the first statement of the non-dry-run branch** — i.e.
between the current line 316 (`elif [ "$DRY_RUN" != "1" ]; then`) and the current
line 317 (`if [ ! -e "$agent_link" ] …`):

```bash
    mkdir -p "$AGENTS_DST"
```

Placement rationale: it must be inside the `elif [ "$DRY_RUN" != "1" ]` branch so a
dry run still writes nothing (the same rule lines 83-90 enforce for
`rsync_and_chmod`), and it must be inside the `kind != command` path so a
command-only deploy does not create an `agents/` directory it will never use — the
`if [ "$kind" = "command" ]` arm at 314-315 already returns before it.

**Permissions caveat, and a hardened alternative.** A bare `mkdir -p` inherits group
and setgid from the parent. When `$DEPLOY_ROOT/opencode` already exists (the live
case: it is `ps-users`, setgid), the new `agents/` lands correctly. When
`$DEPLOY_ROOT/opencode` does **not** exist, `mkdir -p` also creates *it* directly
under `$DEPLOY_ROOT`, which `docs/deploy-permissions.md` measured as setgid
`ps-data` — so the new tree would come out `ps-data`, the exact mistake
`ensure_claude_root()` (lines 144-163) was written to prevent on the claude side. If
the implementer wants the hardened form, add a sibling of `ensure_claude_root`:

```bash
ensure_opencode_root() {
  [ "$DRY_RUN" = "1" ] && return 0
  mkdir -p "$AGENTS_DST"
  chgrp "$GROUP" "$DEPLOY_ROOT/opencode" "$AGENTS_DST" 2>/dev/null || \
    echo "WARN: chgrp $GROUP failed on $DEPLOY_ROOT/opencode"
  # ABSOLUTE mode; chgrp CLEARS setgid, so this MUST come after it (§3).
  chmod 2750 "$DEPLOY_ROOT/opencode" "$AGENTS_DST" 2>/dev/null || \
    echo "WARN: chmod 2750 failed on $DEPLOY_ROOT/opencode"
}
```

and call `ensure_opencode_root` at the same insertion point instead. **Recommended:
ship the one-line `mkdir -p` as the fix (it is the stated defect) and the
`ensure_opencode_root` form as a follow-up**, because changing the mode of the
*live* `$DEPLOY_ROOT/opencode` is a permissions change on a directory 3748 people
read, and that belongs in its own reviewed change, not bundled with a rendering
redesign. Note that `chmod 2750` on the live `opencode/` would clear `other::r-x`
— verify against `docs/deploy-permissions.md` §4 before running it anywhere real.

### C5. `DEPLOY_CLAUDE=1` under the new design

The default stays `1`. **But justification #1 in the comment at lines 53-61 and in
`docs/design-single-source-skills.md` §6 is now false and must be rewritten.** It
reads:

> the claude tree is written ONLY for migrated repos, so with zero external repos
> migrated today this flag changes nothing about what a real deploy produces

Under this design **all 17 entries render**, so on the first full deploy
`DEPLOY_CLAUDE=1` creates `$DEPLOY_ROOT/claude/` and writes **17 skill directories
plus their assets** into it. The flag's blast radius goes from empty to the whole
fleet in one step. Consequences to flag:

1. **`ensure_claude_root()` runs for real, on the real deploy root, for the first
   time.** It has only ever been exercised against a fake root
   (`docs/iteration-4-report.md`). If its `chgrp $GROUP` / `chmod 2750` misfires,
   the result is a new tree under a world-readable parent with the wrong group —
   the 2026-02-12 incident class. Mitigation in §F.2.
2. **Storage and inodes.** 17 skill trees including `references/` and `scripts/`
   assets, duplicated across `claude/` and `opencode/`. Measure the staged size
   before deploying; it is small, but "small" should be a number, not an adjective.
3. **The claude-side descriptions change.** Anyone already pointing
   `CLAUDE_CONFIG_DIR` at a hand-made tree, or reading the repos directly, sees the
   deployed `description:` become `harness.description_auto` from the manifest
   rather than the repo's own text. If `description_auto` was seeded by copying the
   repo's existing description (recommended, §F.3), this is a no-op; if anyone
   "improves" the text while seeding, auto-trigger behaviour changes fleet-wide.
4. **Recommendation:** keep the default at `1`, but run the *first* live deploy with
   `DEPLOY_CLAUDE=0` after a full `DEPLOY_ROOT=/tmp/mhr-mock-deploy` rehearsal with
   `DEPLOY_CLAUDE=1`. Inspect the mock `claude/` tree's modes and groups, then run
   live with the default. Two runs, one new tree, no surprises.

---

## D. The validator

**Filename: `validate-manifest.sh`**, in the repo root next to `deploy.sh` and
`render.sh`. Not under `tools/` — `tools/` is a deploy destination
(`$TOOLS_DST`, line 30) and anything placed there gets rsynced to the shared tree.

**Interface**

```
./validate-manifest.sh [<manifest>]      # default: ./skills.manifest.json
./validate-manifest.sh --counts [<manifest>]   # print only the two proof counts
```

**Exit codes (as shipped — this table was inverted in the iteration-1 draft and
is corrected here to match the code, which is what a human actually runs):**

| code | meaning |
|---|---|
| `0` | every entry carries a well-formed harness block (warnings may still be printed) |
| `1` | usage error, missing/unreadable manifest, or the manifest is not valid JSON |
| `2` | one or more **validation** failures |

The split is deliberate and worth preserving: `1` means *the validator could not
run* — bad arguments, no such file, not JSON — while `2` means *the validator ran
and the manifest is bad*. A caller can therefore distinguish "my invocation is
wrong" from "my manifest is wrong" without parsing output. Verified against the
shipped script:

```
$ ./validate-manifest.sh skills.manifest.json          ; echo $?   # 0
$ ./validate-manifest.sh /tmp/broken.json              ; echo $?   # 2  (harness.kind = "bogus")
$ ./validate-manifest.sh /tmp/does-not-exist.json      ; echo $?   # 1
$ ./validate-manifest.sh /tmp/not-json.txt             ; echo $?   # 1
```

Note that a *warning* never changes the exit code: the real manifest exits `0`
with 17 warnings today (every `description_menu` is over 120 chars, because it is
still a verbatim copy of `description_auto` — see §A.4).

**Checks, in order.** Structural failures short-circuit; per-entry failures do not —
the script reports **all** of them before exiting, because an operator fixing a
manifest wants the whole list, not the first line.

*Manifest-level*
1. file exists and is readable.
2. `jq -e . "$MANIFEST" >/dev/null` — valid JSON.
3. `.skills` exists and is an array (`jq -e '.skills | type == "array"'`).
4. `.skills | length > 0`.
5. every `.name` is a non-empty string, contains no `/`, and is **unique** across
   entries.
6. every `.repo` is a non-empty string matching `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`.

*Per entry*
7. `harness` is present and `type == "object"`.
8. `description_auto` present, `type == "string"`, non-empty after trimming.
9. `description_menu` present, `type == "string"`, non-empty after trimming.
10. `kind`, if present, is `"skill"` or `"command"`.
11. `source`, if present: string, non-empty, no leading `/`, no `..` path segment,
    no trailing `/` (or normalise-and-warn).
12. `name` / `slug`, if present: non-empty strings containing no `/` (the
    `mktemp -d "…-$SLUG-XXXXXX"` dependency, §B4).
13. `argument_hint`, if present: string.
14. `user_invocable`, if present: boolean.
15. **WARN, not FAIL**: `kind == "skill"` together with `argument_hint` or
    `user_invocable` — those keys are only emitted for commands
    (`emit_frontmatter`, render.sh lines 191-204), so setting them on a skill is
    dead metadata.
16. **WARN, not FAIL**: `description_menu` longer than ~120 characters — it is an
    `@`-menu label (design doc §1d). Length is a style judgement, never a gate.

**Output** — one line per entry, then a summary:

```
── skills.manifest.json
  ✓ cuda-docs                harness: kind=skill source=claude/skills/cuda-docs
  ✓ ask-epics                harness: kind=skill source=claude/skills/ask-epics
  …
  ✗ docs-search              harness.description_menu is missing or empty
  ! xpm-seq                  WARN: kind=skill but argument_hint is set (ignored)

17 entries: 16 with a harness block, 1 without.
FAIL: 1 entry has no usable harness block, 1 warning.
```

and on success the last two lines are

```
17 entries: 17 with a harness block, 0 without.
OK: every entry carries a well-formed harness block.
```

**The two proof counts the campaign needs — jq 1.6 compatible, verbatim:**

count of entries WITH a harness block:

```sh
jq '[.skills[] | select((.harness | type) == "object")] | length' skills.manifest.json
```

count of entries WITHOUT one:

```sh
jq '[.skills[] | select((.harness | type) != "object")] | length' skills.manifest.json
```

Both rely only on `type` on a possibly-missing key (`null | type` is `"null"` in
jq 1.6), `select`, array construction and `length` — no `pick`, no `getpath`
defaults, no jq 1.7 idioms. They are exact complements, so they always sum to
`jq '.skills | length'`, which is the property that makes them usable as a proof.

**Implementation note.** Do the per-entry work in one `jq` pass that emits a TSV of
`name<TAB>status<TAB>message`, then let bash format and count. Do not call `jq` once
per entry per check — that is 17 × 10 subprocesses for a file that fits in a
terminal. Under `set -euo pipefail`, remember that a `jq -e` used for a boolean test
must sit inside an `if`.

---

## E. The native-frontmatter fixture

Proves the three things this change turns on: exactly one frontmatter block in each
rendered file, the block carries the **deployer's** description, and the repo's own
description is gone — with a `---` horizontal rule surviving in the body.

### E.1 Build the fixture

```sh
set -e
rm -rf /tmp/mhr-fixture
mkdir -p /tmp/mhr-fixture/repo/claude/skills/demo-skill/references

cat > /tmp/mhr-fixture/repo/claude/skills/demo-skill/SKILL.md <<'EOF'
---
name: demo-skill
description: REPO-SIDE DESCRIPTION - must not survive rendering.
---

# Demo skill

Body line one.

---

Body line after a horizontal rule.
EOF

echo 'asset payload' > /tmp/mhr-fixture/repo/claude/skills/demo-skill/references/note.txt

cat > /tmp/mhr-fixture/meta.json <<'EOF'
{
  "source": "claude/skills/demo-skill",
  "name": "demo-skill",
  "kind": "skill",
  "slug": "demo-skill",
  "description_auto": "DEPLOYER AUTO description. Use when the user asks about the manifest-harness fixture.",
  "description_menu": "DEPLOYER MENU description."
}
EOF
```

Source `SKILL.md` is exactly 12 lines: `1 ---`, `2 name:`, `3 description:`,
`4 ---`, `5 blank`, `6 # Demo skill`, `7 blank`, `8 Body line one.`, `9 blank`,
`10 ---`, `11 blank`, `12 Body line after a horizontal rule.`

### E.2 Render

```sh
cd /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode
./render.sh --meta /tmp/mhr-fixture/meta.json \
            /tmp/mhr-fixture/repo/claude/skills/demo-skill \
            /tmp/mhr-fixture/out
```

Expected stdout:

```
── demo-skill (kind=skill, name=demo-skill) from /tmp/mhr-fixture/repo/claude/skills/demo-skill
  ✓ /tmp/mhr-fixture/out/claude/skills/demo-skill/
  ✓ /tmp/mhr-fixture/out/opencode/skills/demo-skill/
  ✓ /tmp/mhr-fixture/out/opencode/agents/demo-skill -> ../skills/demo-skill
```

### E.3 Proofs

**Claude side — head:**

```sh
head -5 /tmp/mhr-fixture/out/claude/skills/demo-skill/SKILL.md
```

expected, exactly (line 5 is blank):

```
---
name: demo-skill
description: DEPLOYER AUTO description. Use when the user asks about the manifest-harness fixture.
---

```

**opencode side — head:**

```sh
head -5 /tmp/mhr-fixture/out/opencode/skills/demo-skill/SKILL.md
```

expected, exactly:

```
---
name: demo-skill
description: DEPLOYER MENU description.
---

```

Note the two differ **only** on line 3 — same body, two descriptions, from one
render invocation.

**Exactly one frontmatter block, and the horizontal rule survived:**

```sh
grep -n '^---$' /tmp/mhr-fixture/out/claude/skills/demo-skill/SKILL.md
```

expected, exactly three lines:

```
1:---
4:---
10:---
```

Read it as: the leading block is lines 1-4 (opened at 1, closed at 4, nothing
between them but the two key lines), and the `---` at line 10 is the body's
horizontal rule, carried through untouched. **Do not use `grep -c '^---$'` as the
one-block proof** — it returns `3` here for a *correct* render, because the body
legitimately contains a rule. Line numbers are the honest proof; a raw count is
not. Same command on the opencode file gives the same three line numbers.

**The repo's own description is gone (both sides):**

```sh
grep -c 'REPO-SIDE' /tmp/mhr-fixture/out/claude/skills/demo-skill/SKILL.md   || true
grep -c 'REPO-SIDE' /tmp/mhr-fixture/out/opencode/skills/demo-skill/SKILL.md || true
```

expected output: `0` then `0`. (`grep -c` exits 1 on zero matches; the `|| true`
keeps it from tripping `set -e` in a scripted run.)

**The deployer's description is present exactly once per side:**

```sh
grep -c 'DEPLOYER AUTO' /tmp/mhr-fixture/out/claude/skills/demo-skill/SKILL.md
grep -c 'DEPLOYER MENU' /tmp/mhr-fixture/out/opencode/skills/demo-skill/SKILL.md
grep -c 'DEPLOYER MENU' /tmp/mhr-fixture/out/claude/skills/demo-skill/SKILL.md   || true
```

expected: `1`, `1`, `0`.

**The body is intact and the asset shipped:**

```sh
tail -n +5 /tmp/mhr-fixture/out/claude/skills/demo-skill/SKILL.md
cat /tmp/mhr-fixture/out/claude/skills/demo-skill/references/note.txt
```

expected:

```

# Demo skill

Body line one.

---

Body line after a horizontal rule.
asset payload
```

**Negative fixture — unterminated frontmatter (B2's must-not-eat-the-file rule):**

```sh
mkdir -p /tmp/mhr-fixture/bad/claude/skills/demo-skill
printf -- '---\nname: broken\n\n# Body that must survive\n' \
  > /tmp/mhr-fixture/bad/claude/skills/demo-skill/SKILL.md
./render.sh --meta /tmp/mhr-fixture/meta.json \
            /tmp/mhr-fixture/bad/claude/skills/demo-skill \
            /tmp/mhr-fixture/out-bad
grep -c 'Body that must survive' /tmp/mhr-fixture/out-bad/claude/skills/demo-skill/SKILL.md
```

expected: a `WARN: … frontmatter block is never closed …` on stderr, exit 0, and
`1` from the `grep -c` — the body survived rather than being eaten.

---

## F. Risks

Ranked. The first three are the ones that can hurt production.

### F.1 A bare `./deploy.sh` reverts the five unpushed cron fixes — 3748 readers → 61

> **Status: UNCHANGED PRE-EXISTING HAZARD. Still real — re-verified 2026-08-27
> against the live tree, byte for byte, all five.** This change neither causes nor
> cures it. It is recorded here because anyone deploying this work will trip it.

**Re-verification, 2026-08-27.** Each pristine clone's cron script was compared
against the live deployed copy (read-only on the live side). Repo → tools dir
mapping matters and is easy to get wrong — the GitHub repo is `skill-ask-<x>` but
the clone dir is `ask-<x>` and the tools dir is `<y>-docs`:

| repo / clone | tools dir | line | staging (repo `main`) | live deployed |
|---|---|---|---|---|
| `skill-ask-epics` / `ask-epics` | `epics-docs` | 51 | `chgrp -R ps-data "$EPICS_DOCS_DATA_DIR"` | `chgrp -R ps-users …` |
| `skill-ask-nersc` / `ask-nersc` | `nersc-docs` | 37 | `chgrp -R ps-data "$NERSC_DOCS_DATA_DIR"` | `chgrp -R ps-users …` |
| `skill-ask-s3df`  / `ask-s3df`  | `sdf-docs`   | 38 | `chgrp -R ps-data "$SDF_DOCS_DATA_DIR"`   | `chgrp -R ps-users …` |
| `skill-ask-tiled` / `ask-tiled` | `tiled-docs` | 37 | `chgrp -R ps-data "$TILED_DOCS_DATA_DIR"` | `chgrp -R ps-users …` |
| `skill-ask-olcf`  / `ask-olcf`  | `olcf-docs`  | 38 | `chgrp -R ps-data "$OLCF_DOCS_DATA_DIR"`  | `chgrp -R ps-users …` |

Five for five: the divergence is exactly one line per repo, and it is still there.

**Blast radius, measured, not assumed.** `getent group` on the deploy host today:
`ps-users` has **3748** members, `ps-data` has **61**. A revert therefore removes
read access from 3687 people per corpus, across five corpora.

**Time to first damage: under one hour.** `sdf-docs-cron.sh` sets
`CRON_SCHEDULE="${CRON_SCHEDULE:-0 * * * *}"` — hourly, on `sdfcron001`. The revert
is not latent until someone notices; the next top of the hour applies it.

**The fixes exist and are one merge away.** Five branches, each a single commit
`Fix cron chgrp target: ps-data -> ps-users`, live at
`/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/iter6-cron-fix/skill-ask-{epics,nersc,s3df,tiled,olcf}`
on branch `fix/cron-chgrp-ps-users`. They are **committed and unpushed** — `main`
in each tracks `origin/main`, the fix branch has no upstream — so a `deploy.sh`
that clones from GitHub cannot see them.

`skill-ask-{epics,nersc,s3df,tiled,olcf}` each carry one divergent line in
`tools/<x>/scripts/<x>-cron.sh`: the repo `main` says `chgrp -R ps-data
"$<X>_DOCS_DATA_DIR"` while the live tools tree says `ps-users`. The fixes exist
only as five local, **unpushed** branches (`docs/cron-script-divergence.md`).
`deploy.sh` rsyncs `$stage/tools/*/` to `$TOOLS_DST/<x>/` unconditionally at lines
344-353, so any deploy of those five names overwrites the live scripts with the
`ps-data` version, and the next cron fire re-chgrps the corpora from `ps-users`
(3748 readers) to `ps-data` (61).

**Does this change affect it? No — neither way.** Nothing in this spec touches
lines 344-353, the `tools/` exclusion rules, or the clone/fetch step. The hazard is
identical before and after, and it is triggered by *any* deploy of those five
entries, whether they render from a harness block or from the legacy tree.

**Mitigations, all still required:**
- Merge and push the five branches to `main` **before** any full `./deploy.sh`.
  This is the real fix; everything below is a stopgap.
- Until then, deploy by explicit name only, excluding the five:
  `./deploy.sh cuda-docs ask-ami ask-lcls2 …`.
- Add a pre-flight assertion to whatever runbook drives the campaign: for each of
  the five, `grep -c 'chgrp -R ps-users' <clone>/tools/<x>/scripts/<x>-cron.sh`
  must be `1` before the deploy is allowed to proceed.
- Related and still open, out of scope here: `tiled-docs-cron.sh` and
  `olcf-docs-cron.sh` are mode `0644` on both sides, so the tiled cron has never
  successfully run. `rsync -a` preserves the mode, so a deploy neither fixes nor
  worsens it.

### F.2 First deploy populates `$DEPLOY_ROOT/claude/` for real, with untested permissions

Per §C5: today `DEPLOY_CLAUDE=1` writes nothing because nothing is migrated; after
this change it writes 17 skill trees into a directory that does not yet exist, using
an `ensure_claude_root()` path only ever exercised against a fake root. A wrong
group or a stray `other::r-x` on `$DEPLOY_ROOT/claude` is the 2026-02-12 incident
class, on a parent (`/sdf/group/lcls`) that is world-`rx` all the way down.

**Mitigation:** full rehearsal with `DEPLOY_ROOT=/tmp/mhr-mock-deploy` and
`DEPLOY_CLAUDE=1`; then `ls -ld` / `stat -c '%A %G'` every directory it created and
compare against `docs/deploy-permissions.md` §4's prescribed `2750` / `drwxr-s---`
/ `ps-users`; then first live run with `DEPLOY_CLAUDE=0`; then live with the
default. Do not skip the mock — `/tmp/mhr-mock-deploy` already exists for it.

### F.3 All 17 opencode `SKILL.md` files change content in one deploy

Every deployed `opencode/skills/<name>/SKILL.md` gets a **new** frontmatter block
built from `harness.description_menu`, replacing the one the repo ships. That is 17
live files changing at once, on the tree opencode users actually load. A wrong,
truncated or accidentally-empty `description_menu` breaks the `@`-menu label for
that skill; a systematic mistake (e.g. seeding all 17 from the wrong field) breaks
all of them.

**Mitigations:**
- Seed `description_auto` **and** `description_menu` from each repo's existing
  `description:` verbatim, exactly as `migrate.sh` did (lines 160-169: "migration
  never invents copy it was not given"). Shortening `description_menu` is a separate,
  later, human edit, one skill at a time.
- Run `validate-manifest.sh` (§D) as a hard gate. Exit 0 or no deploy.
- Run `render.sh --meta … --check --target opencode <srcdir> /sdf/group/lcls/ds/dm/apps/dev`
  for all 17 first. The expected diff is **frontmatter-only**; anything touching the
  body or the assets is a stop-the-line finding.
- Stage into `/tmp/mhr-mock-deploy` and `diff -r` against `/tmp/mhr-live-snapshot`.
  Read the whole diff before deploying.

### F.4 The frontmatter stripper eats a body

Two shapes: an unterminated opening `---`, and a document whose *first* line is a
`---` horizontal rule (a legal Markdown thematic break) that happens to be followed
by another `---`. The first is handled (pass through + WARN, §B2). The second is
indistinguishable from real frontmatter by any rule and would silently delete the
text between the two rules.

**Mitigation:** the §E negative fixture for the unterminated case; and, for the
second, the `--check` gate in F.3 — a stripped horizontal-rule block shows up as a
body diff, which is already a stop-the-line finding. None of the 17 has a
first-line horizontal rule (all 17 begin with real frontmatter, verified
2026-08-27).

### F.5 `source` defaults to the *claude* side while today's deploy ships the *opencode* side

`deploy.sh` currently rsyncs `$stage/opencode/skills/$name/`. The default
`harness.source` is `claude/skills/<name>`. Today that is a distinction without a
difference — all 17 are byte-identical across the two trees (verified 2026-08-27).
If any repo drifts between that verification and the switch, the deployed body
silently changes sides.

**Mitigation:** re-run the byte-identity check immediately before the switch and
record the hashes; write `source` out **explicitly** in all 17 manifest entries
rather than relying on the default (§A.4), and make `deploy.sh` echo the resolved
source dir unconditionally (§C3, the line 241 change) so the deploy log names which
tree was used.

### F.6 Asset-set changes from moving `$SRC` into the repo

With `$SRC = <stage>/claude/skills/<name>`, the repo-root `README.md` stops shipping
into the rendered trees, and the unanchored `tools/` exclusion would silently drop a
`tools/` directory *inside* a skill dir if one ever appeared.

**Mitigation:** per repo, `diff <(cd <live>/opencode/skills/<name> && find . | sort)
<(cd <rendered> && find . | sort)` — expect only `SKILL.md` content to differ, and
no file to appear or disappear. Any add/remove is a finding. (Run it with `bash -c`
on the host: `/bin/sh` there rejects process substitution.)

### F.7 Manifest becomes a single point of failure for all 17

Metadata for 17 skills now lives in one JSON file. A malformed edit — an unescaped
quote inside a trigger-dense `description_auto`, a trailing comma — breaks the whole
deploy, where a per-repo `skill.json` would have broken one. Blast radius went up by
17×.

**Mitigation:** `validate-manifest.sh` as a pre-commit and pre-deploy gate; and
`deploy.sh` should validate the manifest is parseable *before* the loop (a bare
`jq -e . "$MANIFEST" >/dev/null || { echo …; exit 1; }` next to the existing
`[ ! -f "$MANIFEST" ]` check at lines 358-361), so a syntax error fails in one
second instead of after 17 clones.

### F.8 Temp-file lifecycle under `set -euo pipefail`

`META_DIR` is created before the trap in §C1's ordering; if the implementer inverts
those two lines, `set -u` fires inside the trap. `jq -e` returning 4 on an empty
result aborts the run if not wrapped in an `if`. A `trap … EXIT INT TERM` that is
later overwritten by a second `trap` silently leaks the directory.

**Mitigation:** exactly one `trap` in `deploy.sh`; assign then trap, in that order;
the `if jq -e` form as written; and verify with
`DEPLOY_ROOT=/tmp/mhr-mock-deploy ./deploy.sh cuda-docs` followed by
`ls -d /tmp/deploy-harness-* 2>/dev/null` returning nothing.

### F.9 A typo'd `harness` key silently reverts an entry to the legacy path

Keeping the legacy branch (§C2.1) means `"harnes": {…}` deploys the old way and
reports success.

**Mitigation:** the present-but-malformed case is already a hard error (§C1), and
the validator's count of entries *without* a harness block (§D) is the campaign's
proof metric — `17 with, 0 without` is exactly the assertion that catches this.

### F.10 jq 1.6 / bash 4.4.20 / rsync 3.1.3 on the deploy host

No `pick` (1.7), no bash 5 features, no `rsync --mkpath`, and `bridge bash` runs
`/bin/sh` so process substitution needs an explicit `bash -c` wrapper.

**Mitigation:** every expression in this spec was written for and checked against
jq 1.6 and bash 4.4; the `awk` BOM escape is octal for mawk portability (§B2). Run
`validate-manifest.sh` and `render.sh` on **sdfiana025**, not locally, before
trusting either.

### F.11 `render.sh` is untracked and `deploy.sh` is uncommitted

Both live only in the working tree. A `/tmp` wipe does not touch them, but a stray
`git checkout` does for `deploy.sh`, and nothing at all protects `render.sh`.

**Mitigation:** copy both to `/tmp/mhr-recon/` before editing. Committing is out of
scope for this campaign per the guardrails and stays that way.

---

## G. Recommendation on `migrate.sh`

`migrate.sh` is the **third writer of `skill.json`** (writes it at line 169, excludes
it from assets at lines 180 and 195). Its entire job is to derive
`{skill.json, frontmatter-free SKILL.md, assets}` from an existing duplicated
`claude/` + `opencode/` pair.

**Recommendation: do NOT rework it. Mark it DEPRECATED now; delete it when the
`deploy-opencode` repo's own `src/<slug>/` migration is formally closed out.**

Reasoning:

1. **Reworking is pointless.** Under this design the 17 repos keep their dual tree
   unchanged and `render.sh` strips the frontmatter itself (§B2). The output
   `migrate.sh` produces — a `skill.json` plus a stripped body — is exactly the
   thing this change exists to stop requiring. There is nothing left for it to
   produce that anyone consumes.
2. **Deleting it today is premature.** `render.sh` keeps the `skill.json` fallback
   (§B1) precisely for the `deploy-opencode` repo's own `src/<slug>/` shape, which
   is still an open item in `docs/design-single-source-skills.md` §8 ("Migrating the
   deploy-opencode repo's own skills"). `migrate.sh` is the only tool that produces
   that shape. Deleting the producer while keeping the consumer is the worse of the
   two errors.
3. **It is not in the deploy path.** `deploy.sh` never invokes it; it is untracked
   scaffolding, run by hand. Leaving it in place costs nothing operationally, and
   its own header already says "delete it once the 15 skill-* repos have moved" —
   which, under this design, they never will, because they never move at all.

Concrete action for the implementing agent: add two lines to `migrate.sh`'s header
comment (which `usage()` sed-prints via `sed -n '2,26p'`, line 37 — **update that
range if you add lines**):

```
# DEPRECATED as of docs/design-manifest-harness.md: the 17 external repos keep
# their existing layout and need no skill.json. Only the deploy-opencode repo's
# own src/<slug>/ migration still consumes this. Delete when that closes.
```

Do not touch its logic.

---

## H. Implementation order

1. `validate-manifest.sh` (§D) — new file, no dependencies, provably safe.
2. Add the 17 `harness` blocks to `skills.manifest.json` (§A), descriptions copied
   verbatim from each repo's `claude/skills/<name>/SKILL.md` frontmatter. Run
   `validate-manifest.sh` → expect `17 with, 0 without`.
3. `render.sh` §B1 + §B2 + §B4. Build and run the §E fixture, including the negative
   one. This is the gate: no fixture, no deploy.sh change.
4. `deploy.sh` §C4 (the one-line `AGENTS_DST` fix) — independent of everything else,
   land it first among the deploy.sh edits.
5. `deploy.sh` §C1 + §C2 + §C3 + the §C5 comment rewrite.
6. `DEPLOY_ROOT=/tmp/mhr-mock-deploy ./deploy.sh` full rehearsal;
   `diff -r` against `/tmp/mhr-live-snapshot`; audit modes and groups (§F.2).
7. `render.sh --check` all 17 against the live tree (§F.3). Frontmatter-only diffs
   or stop.
8. Only then, and only after the five cron branches are pushed (§F.1), a real
   deploy — first with `DEPLOY_CLAUDE=0`, then with the default.
