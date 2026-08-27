# Iteration 4: the Claude Code deploy target, and three bug fixes

Predecessors: `docs/design-single-source-skills.md` (the design),
`docs/render-equivalence-report.md` (iteration 1), `docs/iteration-2-report.md`
(the `deploy.sh` wiring), `docs/iteration-3-pilot-report.md` (the askcode merge
and the first external repo).

Everything below was run on **sdfiana025** on 2026-08-26. `DEPLOY_ROOT` was
**never** the real one; every deploy went into a fake root under `/tmp`.
`/sdf/group/lcls/ds/dm/apps/` was read, never written.

## 0. Summary

| item | outcome |
|---|---|
| Bug 1 — in-place render not idempotent | **Fixed.** Anchored build-output excludes. Regression test: render twice in place, `diff -r`, empty. §1 |
| Bug 2 — `--check` reports a spurious `.rendered` | **Fixed** by the same change. Regression test: `--check <stage> <stage>/.rendered` now reports `matches`, exit 0. §1 |
| Bug 3 — `deploy.sh` pins the source dir to the repo root | **Fixed.** `resolve_source_dir()`, three-rule order; a repo matching neither shape is now an `ERROR` and exit 3. §2 |
| Claude Code deploy target | **Built.** `$DEPLOY_ROOT/claude/skills/<name>/` and `$DEPLOY_ROOT/claude/commands/<name>.md`, default-on, no agents symlink. §3 |
| Unmigrated repos unchanged | **Proven byte-identical**, stdout and tree, real run and dry run. §4 |
| End-to-end discovery by Claude Code 2.1.235 | **Works.** Both deployed skills and the deployed command discovered from a fake root, with a negative control. §5 |
| New finding: group ownership of the new tree | `$DEPLOY_ROOT` is setgid `ps-data` while `opencode/` is `ps-users`; a bare `mkdir` would have created `claude/` in the wrong group. Handled in `deploy.sh`. §3.4 |

Files changed in the remote working tree (uncommitted, as everything in this
series is):

```
render.sh    md5 231fe117… -> 17a77670…    +24 / -3
deploy.sh    md5 39e41402… -> 9637d35a…    +162 / -20
docs/design-single-source-skills.md         §5, §6, §8 rewritten
docs/iteration-4-report.md                  new (this file)
```

## 1. Bugs 1 and 2 — one root cause, one fix

### 1.1 Reproduced first, with the pre-change `render.sh`

Snapshot taken before touching anything:
`/tmp/it4/pre/render.sh.orig`, md5 `231fe11798a24105471244758773ee24`.

Source dir with `skill.json`, `SKILL.md`, `README.md`, `references/note.md`.
One in-place render:

```
$ /tmp/it4/pre/render.sh.orig src src
── b1 (kind=skill, name=b1) from src
  ✓ src/claude/skills/b1/
  ✓ src/opencode/skills/b1/
  ✓ src/opencode/agents/b1 -> ../skills/b1

$ find src | sort
...
src/opencode/skills/b1/claude/skills/b1/README.md          <-- the claude pass's
src/opencode/skills/b1/claude/skills/b1/references/note.md      output, shipped as
                                                                an ASSET
```

The corruption is present after **one** run, not two. A second run:

```
README.md copies after 2 runs: 12
deepest: src/opencode/skills/b1/claude/skills/b1/opencode/skills/b1/claude/skills/b1/README.md
```

Bug 2, same fixture shape, pointed at a `deploy.sh`-style staging dir:

```
$ render.sh.orig --target opencode /tmp/it4/bug2/stage /tmp/it4/bug2/stage/.rendered
  ✓ /tmp/it4/bug2/stage/.rendered/opencode/skills/b2/
$ render.sh.orig --check --target opencode /tmp/it4/bug2/stage /tmp/it4/bug2/stage/.rendered
  ✗ DIFFERS /tmp/it4/bug2/stage/.rendered/opencode/skills/b2/
      Only in /lscratch/cwang31/tmp/check-b2-4bBMeb: .rendered
```

The staging dir contains only `skill.json`, `SKILL.md` and `.rendered` — the
`.rendered` dir `deploy.sh` itself left there. `--check` renders into a temp dir,
rsyncs the source over it, and the source now contains `.rendered`. Exactly the
same root cause as bug 1: **build outputs at the source root were being treated
as assets.**

### 1.2 The fix, and why the suggested one is right

The brief suggested anchoring excludes for `claude`, `opencode` and `.rendered`
into `ASSET_EXCLUDES` and `has_assets`. Adopted, with the anchoring taken
seriously:

```bash
ASSET_EXCLUDES=(
  --exclude='skill.json' --exclude='SKILL.md'
  --exclude='.git/' --exclude='tools/'
  --exclude='/claude/' --exclude='/opencode/' --exclude='/.rendered/'
)
```

and `claude|opencode|.rendered` added to the `continue` list in `has_assets()`
so a `kind=command` source dir that has already been rendered in place does not
suddenly fail the "commands cannot have assets" check.

Three things were checked before adopting it rather than after:

- **The leading `/` matters.** An rsync exclude pattern without a leading slash
  matches at *every* depth, so a bare `--exclude='opencode/'` would silently drop
  a legitimate `references/opencode/` asset directory. Anchored, it matches only
  at the transfer root. This is tested (§1.3): the fixture carries
  `references/opencode/keepme.md` and it survives.
- **The fix is correct independently of the in-place case.** §3 of the design doc
  already says `claude/` and `opencode/` are generated, gitignored build outputs.
  A repo mid-migration that still carries stale pre-migration harness trees would
  have shipped them *inside* the rendered skill even with `<output-dir>` outside
  `<source-dir>`. So this is not a workaround for in-place rendering; it is the
  rule that was missing.
- **`.git/` and `tools/` were deliberately left unanchored.** A nested `.git` is
  never an asset at any depth (design doc §7 names a real nested clone in this
  repo). Anchoring `tools/` would arguably be truer to §2, but it is a behaviour
  change with no motivating bug and it sits outside this iteration's scope; it is
  noted, not done.

The alternative considered and rejected: having `deploy.sh` render *outside* the
staging dir, so the staging dir never contains `.rendered`. That would fix bug 2
without teaching `render.sh` about `deploy.sh`'s directory name — but it fixes
nothing about bug 1, nothing about stale harness trees in a source repo, and it
would have changed the render output paths that iteration 3 verified. The
exclusion is cheap and strictly more general.

### 1.3 Regression test 1 — render twice in place

The fixture additionally carries `references/opencode/keepme.md`, to pin the
anchoring.

```
$ render.sh src src ; cp -a src snap1 ; render.sh src src ; cp -a src snap2
── b1 (kind=skill, name=b1) from src
  ✓ src/claude/skills/b1/
  ✓ src/opencode/skills/b1/
  ✓ src/opencode/agents/b1 -> ../skills/b1
── b1 (kind=skill, name=b1) from src
  ✓ src/claude/skills/b1/
  ✓ src/opencode/skills/b1/
  ✓ src/opencode/agents/b1 -> ../skills/b1

$ diff -r snap1 snap2
  IDEMPOTENT: no differences

README.md copies after 2 runs: 3          (source + claude tree + opencode tree)

src/claude/skills/b1/{SKILL.md,README.md,references/note.md,references/opencode/keepme.md}
src/opencode/skills/b1/{SKILL.md,README.md,references/note.md,references/opencode/keepme.md}
src/opencode/agents/b1 -> ../skills/b1
```

`references/opencode/keepme.md` is present in both rendered trees — the anchoring
does what it is supposed to.

### 1.4 Regression test 2 — `--check` against a staging dir holding `.rendered`

```
$ ls -a /tmp/it4/r2/stage
.  ..  .rendered  skill.json  SKILL.md

$ render.sh --check --target opencode /tmp/it4/r2/stage /tmp/it4/r2/stage/.rendered
── b2 (kind=skill, name=b2) from /tmp/it4/r2/stage — CHECK against /tmp/it4/r2/stage/.rendered
  ✓ /tmp/it4/r2/stage/.rendered/opencode/skills/b2/ matches
  check exit=0
```

The `tools/skill-drift/` cron would have fired on every migrated skill from day
one. It no longer does.

### 1.5 Regression test 3 — out-of-place rendering is unchanged

The migrated `askcode` source (iteration 3), rendered by the old and the new
`render.sh` into two separate output dirs:

```
OLD ── askcode (kind=skill, name=askcode) from /tmp/it4/r3/src
OLD   ✓ /tmp/it4/r3/out-old/claude/skills/askcode/
OLD   ✓ /tmp/it4/r3/out-old/opencode/skills/askcode/
OLD   ✓ /tmp/it4/r3/out-old/opencode/agents/askcode -> ../skills/askcode
NEW ── askcode (kind=skill, name=askcode) from /tmp/it4/r3/src
NEW   ✓ /tmp/it4/r3/out-new/claude/skills/askcode/
NEW   ✓ /tmp/it4/r3/out-new/opencode/skills/askcode/
NEW   ✓ /tmp/it4/r3/out-new/opencode/agents/askcode -> ../skills/askcode

$ diff -r out-old out-new
  BYTE-IDENTICAL
```

Iterations 1–3's equivalence results are therefore untouched.

## 2. Bug 3 — the source dir was pinned to the repo root

Before: `if [ -f "$stage/skill.json" ]` … `"$RENDER" --target opencode "$stage"`.
A repo using the `src/<slug>/` shape from design doc §3 has no root `skill.json`,
so it fell to the legacy branch, looked for `opencode/skills/<name>/`, found
nothing, printed one `WARN` and exited 0.

### 2.1 The resolution rule

`resolve_source_dir(stage, name)`, first match wins:

1. `<stage>/skill.json` — single-skill repo, the iteration-2 shape.
2. `<stage>/src/<name>/skill.json` — multi-skill repo, manifest name = directory
   name. This is the common case and needs no JSON parsing.
3. any `<stage>/src/*/skill.json` whose `.slug` or `.name` equals the manifest
   name. Covers the `lab-notebook-skill` shape, where the invocation name and the
   directory name genuinely differ.

Chosen over the alternatives:

- *Deploy every `src/*/` in the repo.* Rejected: `deploy.sh` is driven by
  `skills.manifest.json`, which lists one `name` per entry and uses that name for
  the deploy destination. One manifest entry deploying N skills would put content
  at paths the manifest never named.
- *Add a `source` field to the manifest.* Rejected: the manifest deliberately says
  nothing about layout (design doc §6), and a second place to record the shape is
  how drift starts. The repo's own contents are the ground truth.

Rule 2 is tried before rule 3 so the fast path costs no `jq` calls, and rule 3 is
a scan rather than a guess.

### 2.2 Failing loudly

If no rule matches **and** there is no legacy `opencode/skills/<name>/`:

```
── broken (fixture/skill-broken @ main)
  ERROR: fixture/skill-broken matches neither single-source nor legacy layout:
         no skill.json at repo root or src/broken/, and no
         opencode/skills/broken/ directory. Nothing deployed.
...
ERROR: one or more repos matched no known layout; see above.
==> exit=3
```

The rest of the manifest still deploys — one broken repo must not block the fleet
— but the run exits **3** so a cron or a wrapper notices. This is the single
intentional behaviour change for a non-migrated repo, and it can only affect a
repo that was already deploying nothing.

## 3. The Claude Code deploy target

### 3.1 The destinations, and why those names

```bash
CLAUDE_SKILLS_DST="$DEPLOY_ROOT/claude/skills"
CLAUDE_CMDS_DST="$DEPLOY_ROOT/claude/commands"
```

Justification against the existing layout: the opencode tree sits directly under
`$DEPLOY_ROOT` as `opencode/{skills,agents,commands}`, and `CLAUDE.md` documents
every deployed path in the form `/sdf/group/lcls/ds/dm/apps/dev/opencode/…`. A
sibling `claude/` at the same depth is the only choice that keeps the two
harnesses symmetric. Checked read-only that the name is free:

```
$ ls /sdf/group/lcls/ds/dm/apps/dev/
bin  .cache  code  data  env  opencode  python  software  tools
```

No `claude/`. The first real deploy creates it. Nothing was created there by this
iteration.

### 3.2 No agents symlink on the claude side

Deliberate, and it is a correctness point, not a tidiness one. The opencode
`agents/<n> -> ../skills/<n>` symlink exists because opencode resolves `@<n>`
through `agents/`. Claude Code has no such lookup, and its `agents/` directory
holds one `.md` file per subagent — pointing that name at a skill *directory*
would be a malformed subagent, not a no-op. `deploy.sh` creates no such link, and
the fake-root tree confirms it:

```
$ ls ROOT/claude
commands  skills
```

### 3.3 Per-kind routing, and the asymmetry on commands

`kind=skill` → `$DEPLOY_ROOT/claude/skills/<name>/`.
`kind=command` → `$DEPLOY_ROOT/claude/commands/<name>.md`.

`kind=command` does **not** deploy to opencode. `$DEPLOY_ROOT/opencode/commands/`
exists and is live hand-maintained state; adopting it as an rsync destination
would overwrite files nothing in this repo owns, and design doc §6 has always
left it undesigned. The claude commands dir, by contrast, is greenfield. So the
run prints a `NOTE`, not a `WARN` — the command *is* deployed now, just to one
harness:

```
  NOTE: kind=command — claude/commands only; opencode/commands is not
        a deploy destination (design doc §6)
  ✓ claude command
```

### 3.4 Permissions — including a bug the first run exposed

`kind=skill` reuses `rsync_and_chmod` unchanged, so the `chgrp $GROUP` +
`chmod -R g+rX` step applies to the claude tree exactly as to the opencode one.
A rendered command is a single file, not a tree, so it gets
`rsync_file_and_chmod`: no `--delete` (the destination is one named file),
`chgrp` on the file and its parent, `chmod g+rX` on the parent and `g+r` on the
file.

The first fake-root run exposed something the brief did not name.
`rsync_and_chmod` only touches `$dst`, i.e. the per-skill subdirectory. The
*roots* — `$DEPLOY_ROOT/claude` and `$DEPLOY_ROOT/claude/skills` — are created by
`mkdir -p` and inherit whatever the parent gives them. On the real deploy root
that parent is `drwxrwsr-x psdatmgr ps-data`, i.e. **setgid `ps-data`**, while
the sibling `opencode/` tree is `ps-users`. A bare `mkdir` would have created the
whole new tree in the wrong group on the very first production deploy, and no
existing code path would ever have corrected it — `chgrp -R` never reaches a
parent of `$dst`.

`ensure_claude_root()` now `chgrp`/`chmod g+rX`-es the two roots when it first
creates them. It is called lazily, only when something is about to be written, so
`DEPLOY_CLAUDE=1` never leaves an empty tree behind.

### 3.5 Default-on

`DEPLOY_CLAUDE="${DEPLOY_CLAUDE:-1}"`. The reasoning, in the order that decided
it:

1. The claude tree is written **only for migrated repos**. Zero external repos are
   migrated today, so default-on changes nothing about what a real deploy
   produces. The flag's blast radius right now is empty.
2. It is additive: it writes under `$DEPLOY_ROOT/claude/` and modifies no existing
   path. The opencode tree, the agents symlinks and `tools/` are untouched.
3. Nothing reads it until a user opts in by pointing `CLAUDE_CONFIG_DIR` at
   symlinks into it. A tree nobody points at is inert.
4. Default-off would mean the tree never comes into existence and quietly goes
   stale — which is problem (b) in the design doc, the thing this target exists to
   fix. A flag defaulting off would recreate the same failure under a new name.

`DEPLOY_CLAUDE=0` restores the pre-iteration-4 behaviour exactly. Verified:

```
$ DEPLOY_CLAUDE=0 ... deploy.sh askcode
    ✓ /tmp/it4/dep/stage/askcode/.rendered/opencode/skills/askcode/
    ✓ /tmp/it4/dep/stage/askcode/.rendered/opencode/agents/askcode -> ../skills/askcode
  ✓ rendered from skill.json (kind=skill, slug=askcode, target=opencode)
  ✓ skill content
  ✓ agents/ symlink created
$ ls -d ROOT/claude
ls: cannot access '/tmp/it4/dep/root3/claude': No such file or directory
```

Note the render itself drops to `--target opencode`, so the flag saves the work
as well as the copy.

## 4. Unmigrated repos: byte-identical, proven

Method, per iteration 2. `deploy.sh` was snapshotted before any edit
(`/tmp/it4/pre/deploy.sh.orig`, md5 `39e41402926e8bc72b9f8af59d8f578a`). The
legacy fixture is iteration 3's `upstream/skill-askcode-legacy.git` — the current
real `main` of `carbonscott/skill-askcode`, i.e. an actually-unmigrated repo, not
a synthetic one. Each version ran against its own fresh clone into its own fake
root, with `PS_USERS_GROUP` set to the invoking user's group so the `chgrp` step
really ran, and `opencode/agents/` pre-created to get past the pre-existing
`AGENTS_DST` bug iteration 2 recorded.

### 4.1 Real run

```
=== legacy fixture, REAL run: OLD deploy.sh ===   exit=0
=== legacy fixture, REAL run: NEW deploy.sh ===   exit=0

--- normalized stdout diff (empty == identical) ---
  STDOUT IDENTICAL

--- stdout (new) ---
  ── askcode (fixture/skill-askcode-legacy @ main)
  ...
    ✓ skill content
    ✓ agents/ symlink created

  Done. Cron entries are not auto-installed — install manually on sdfcron001
  per the 'cron:' blocks in /tmp/it3-fix/manifest-legacy.json.

--- diff -r of the two deployed trees (empty == identical) ---
  TREES BYTE-IDENTICAL

--- deployed tree ---
  ROOT/opencode/agents/askcode
  ROOT/opencode/skills/askcode/env.sh
  ROOT/opencode/skills/askcode/SKILL.md

--- is there ANY claude/ dir under either fake root? ---
  (no output — nothing deposited in the claude tree)
```

### 4.2 Dry run

Run with equal-length fake-root path names, because rsync's own
`sent N bytes` counter includes the destination path length and would otherwise
differ by three bytes for no interesting reason.

```
=== legacy fixture, DRY_RUN=1: OLD vs NEW, normalized stdout diff ===
  DRY-RUN STDOUT IDENTICAL

  ── askcode (fixture/skill-askcode-legacy @ main)
  sending incremental file list
  SKILL.md
  env.sh
  sent 104 bytes  received 22 bytes  252.00 bytes/sec
  total size is 6,832  speedup is 54.22 (DRY RUN)
    ✓ skill content
    (dry-run) would create ROOT/opencode/agents/askcode
```

## 5. End to end: deploy, then discover

### 5.1 The deploy

Four manifest entries into one fake root `/tmp/it4/dep/root2`:

| entry | fixture | shape |
|---|---|---|
| `askcode` | iteration 3's `skill-askcode.git` (`single-source-migration` as `main`) | root `skill.json`, `kind=skill`, real content |
| `multiskill` | new | `src/multiskill/skill.json`, `kind=skill`, an asset — exercises bug 3 |
| `testcmd` | new | root `skill.json`, `kind=command`, `argument_hint` |
| `broken` | new | neither shape — exercises the loud failure |

```
── askcode (fixture/skill-askcode @ main)
  ── askcode (kind=skill, name=askcode) from /tmp/it4/dep/stage/askcode
    ✓ .../.rendered/claude/skills/askcode/
    ✓ .../.rendered/opencode/skills/askcode/
    ✓ .../.rendered/opencode/agents/askcode -> ../skills/askcode
  ✓ rendered from skill.json (kind=skill, slug=askcode, target=both)
  ✓ skill content
  ✓ claude skill content
  ✓ agents/ symlink created
── multiskill (fixture/skill-multi @ main)
  source dir: src/multiskill (multi-skill repo)
  ── multiskill (kind=skill, name=multiskill) from /tmp/it4/dep/stage/multiskill/src/multiskill
    ✓ .../.rendered/claude/skills/multiskill/
    ✓ .../.rendered/opencode/skills/multiskill/
    ✓ .../.rendered/opencode/agents/multiskill -> ../skills/multiskill
  ✓ rendered from skill.json (kind=skill, slug=multiskill, target=both)
  ✓ skill content
  ✓ claude skill content
  ✓ agents/ symlink created
── testcmd (fixture/skill-testcmd @ main)
  ── testcmd (kind=command, name=testcmd) from /tmp/it4/dep/stage/testcmd
    ✓ .../.rendered/claude/commands/testcmd.md
    ✓ .../.rendered/opencode/commands/testcmd.md
  ✓ rendered from skill.json (kind=command, slug=testcmd, target=both)
  NOTE: kind=command — claude/commands only; opencode/commands is not
        a deploy destination (design doc §6)
  ✓ claude command
  (skipped agents/ symlink: kind=command)
── broken (fixture/skill-broken @ main)
  ERROR: fixture/skill-broken matches neither single-source nor legacy layout:
         no skill.json at repo root or src/broken/, and no
         opencode/skills/broken/ directory. Nothing deployed.

ERROR: one or more repos matched no known layout; see above.
==> exit=3
```

Resulting tree:

```
ROOT/claude/commands/testcmd.md
ROOT/claude/skills/askcode/{SKILL.md,env.sh,README.md,.gitignore}
ROOT/claude/skills/multiskill/{SKILL.md,references/note.md}
ROOT/opencode/agents/askcode    -> ../skills/askcode
ROOT/opencode/agents/multiskill -> ../skills/multiskill
ROOT/opencode/skills/askcode/{SKILL.md,env.sh,README.md,.gitignore}
ROOT/opencode/skills/multiskill/{SKILL.md,references/note.md}
```

Note `ROOT/opencode/commands/` does not exist: the opencode command was rendered
in staging and deliberately not deployed (§3.3).

Group and mode on the new tree (`PS_USERS_GROUP` overridden to `gu`, the
invoking user's group, so the `chgrp` really ran):

```
drwxr-xr-x gu  ROOT/claude
drwxr-xr-x gu  ROOT/claude/commands
-rw-r--r-- gu  ROOT/claude/commands/testcmd.md
drwxr-xr-x gu  ROOT/claude/skills
drwxr-xr-x gu  ROOT/claude/skills/askcode
-rw-r--r-- gu  ROOT/claude/skills/askcode/SKILL.md
...
```

The per-harness description split, visible in the deployed artefacts:

```
ROOT/claude/skills/multiskill/SKILL.md      description: Multi-skill repo pilot. Use when testing src/<slug> resolution.
ROOT/opencode/skills/multiskill/SKILL.md    description: Multi-skill pilot.
```

(`askcode`'s two are identical, because its `skill.json` carries the same string
in both fields — a property of that skill.json, noted in iteration 3, not of the
renderer.)

The deployed command file:

```
---
description: Fixture command, auto text.
argument-hint: "[topic]"
---

Do the thing with $ARGUMENTS.
```

`description_auto` on the claude side, no `name:`, `argument-hint` quoted — the
§5 render rules, in the deployed file.

### 5.2 The throwaway Claude Code config dir

```bash
C=/tmp/it4/ccdir
ln -s /tmp/it4/dep/root2/claude/skills   $C/skills
ln -s /tmp/it4/dep/root2/claude/commands $C/commands
cp claude/settings.template.json         $C/settings.json   # SLAC gateway config
```

```
$ ls -la $C
lrwxrwxrwx commands -> /tmp/it4/dep/root2/claude/commands
lrwxrwxrwx skills   -> /tmp/it4/dep/root2/claude/skills
-rw-r--r-- settings.json
```

`settings.json` is `claude/settings.template.json` verbatim: `apiKeyHelper` →
`/sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat`, `ANTHROPIC_BASE_URL` →
`https://ai-api.slac.stanford.edu`. Read-only use of both.

### 5.3 Skill discovery

The `claude` launcher on PATH is still missing (`/sdf/home/c/cwang31/.local/bin/`),
so the versioned binary was invoked directly.

```bash
CLAUDE_CONFIG_DIR=/tmp/it4/ccdir \
  /sdf/home/c/cwang31/.local/share/claude/versions/2.1.235 \
  -p 'List the names of every Agent Skill available to you, one name per line, nothing else.'
```

exit 0, empty stderr. **Full stdout, not truncated** (the output was written to a
file and counted programmatically — `head`/`tail` would have hidden the answer,
which caught someone earlier in this session):

```
askcode
multiskill
testcmd
dataviz
update-config
keybindings-help
simplify
fewer-permission-prompts
loop
claude-api
run
init
security-review
```

```
askcode      occurrences=1
multiskill   occurrences=1
testcmd      occurrences=1
total lines=13
```

Both deployed skills are discovered from the fake deploy root, through the
symlink, by the real binary.

### 5.4 Command discovery

```bash
CLAUDE_CONFIG_DIR=/tmp/it4/ccdir <binary> \
  -p 'List every custom slash command available to you, one per line, with its description. Nothing else.'
```

Full stdout:

```
/askcode — Code indexing and navigation using tree-sitter; find functions, search structure, analyze call graphs, index repos (Python/C/C++).
/multiskill — Multi-skill repo pilot; used when testing src/<slug> resolution.
/testcmd — Fixture command, auto text.
/dataviz — Design guidance for any chart, plot, dashboard, or data visualization before writing chart code.
/update-config — Configure the Claude Code harness via settings.json: hooks, permissions, env vars.
/keybindings-help — Customize keyboard shortcuts and ~/.claude/keybindings.json.
/simplify — Review changed code for reuse, simplification, efficiency, and altitude cleanups, then apply fixes.
/fewer-permission-prompts — Scan transcripts for common read-only tool calls and add an allowlist to project settings.json.
/loop — Run a prompt or slash command on a recurring interval (defaults to 10m).
/claude-api — Reference for the Claude API / Anthropic SDK: model ids, pricing, params, streaming, tool use, MCP, caching.
/run — Launch and drive this project's app to verify a change works in the real app.
/init — Initialize a new CLAUDE.md file with codebase documentation.
/security-review — Complete a security review of the pending changes on the current branch.
```

`/testcmd` is present, and its description is **`Fixture command, auto text.`** —
`description_auto`, i.e. the string the *claude* render rule selects, not the
`description_menu` (`Fixture command.`) the opencode render would have used. So
the file being read is demonstrably the deployed claude one.

Caveat worth recording: Claude Code presents skills as slash commands too, which
is why `/askcode` and `/multiskill` appear in this list. That does not weaken the
result — a `commands/<name>.md` file was placed by `deploy.sh`, and the harness
picked it up with the right frontmatter — but it does mean this listing alone
cannot distinguish "found in `commands/`" from "found in `skills/`". §5.1's
`ROOT/claude/commands/testcmd.md` and the `description_auto` string are what pin
it down.

### 5.5 Negative control

The trap in an experiment like this is that a skill was already available from
somewhere else. Same binary, same working directory, same `settings.json`, a
config dir with **no** symlinks:

```
$ CLAUDE_CONFIG_DIR=/tmp/it4/ccdir-control <binary> -p 'List the names of every Agent Skill…'
dataviz
update-config
keybindings-help
simplify
fewer-permission-prompts
loop
claude-api
run
init
security-review

askcode      occurrences=0
multiskill   occurrences=0
testcmd      occurrences=0
```

The ten built-ins remain; all three deployed names vanish. Discovery in §5.3 and
§5.4 is attributable to the deployed tree and to nothing else.

## 6. What was NOT verified

Stated as plainly as the successes.

- **Nothing was tested against the real `$DEPLOY_ROOT`.** Every deploy went to a
  `/tmp` fake root, per the constraints. The claude tree does not exist in
  production and this iteration did not create it.
- **The `ps-users` group behaviour on the real root is reasoned, not measured.**
  `$DEPLOY_ROOT`'s setgid `ps-data` bit was read; the consequence for a new
  `claude/` directory was inferred from it and handled, but the only place
  `ensure_claude_root()` has actually run is a fake root where the invoking user
  owns everything. The first production deploy should have
  `ls -ld $DEPLOY_ROOT/claude $DEPLOY_ROOT/claude/{skills,commands}` checked by a
  human.
- **No end-to-end run of an actual *invocation*.** §5 proves the deployed skill
  and command are *discovered*. It does not prove `askcode` works when invoked —
  that needs its `env.sh` and its code index, which live outside the fake root.
  Design doc §8's "verifying that an auto-triggered skill actually fires" is still
  unsolved.
- **`multiskill` and `testcmd` are fixtures**, not real skills. The `src/<slug>/`
  resolution path has never run against a real repo, because no real repo uses
  that shape yet — this repo itself does (`src/`), but it is not deployed through
  the manifest.
- **`DEPLOY_CLAUDE=0` was checked on one skill**, not on the full four-entry
  manifest.
- **The `kind=command` claude-only asymmetry is a decision, not a discovery.** It
  may well be wrong; deploying opencode commands is one small block away, and the
  reason it is not in this iteration is that
  `$DEPLOY_ROOT/opencode/commands/` holds files nothing in this repo owns.
- **No commit, no push, no cron, nothing written under `/sdf/group/lcls/ds/dm/apps/`.**

## 7. Suggested next steps

1. Decide `$DEPLOY_ROOT/opencode/commands/` — either adopt it as a destination
   (and reconcile the hand-maintained files there) or write down that it stays
   hand-maintained forever. The current asymmetry should not be permanent by
   default.
2. Ship the user-side bootstrap. `claude/install-claude-lcls.sh` exists; it should
   create the per-user writable `CLAUDE_CONFIG_DIR` with symlinks into
   `$DEPLOY_ROOT/claude/{skills,commands}`, which §5 proves is the working shape.
3. Migrate one real external repo and run the whole chain against it, so
   `src/<slug>/` and the two-target deploy stop being fixture-only.
4. Install the drift cron. Bug 2 was the blocker; it is fixed.
