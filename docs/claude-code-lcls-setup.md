# Claude Code on the SLAC AI Gateway

Setup guide for LCLS team members who want to run **Claude Code** against SLAC's
own Anthropic-compatible gateway. Everything here was verified on `sdfiana025`
on **2026-08-26** with Claude Code **2.1.235**.

This is a *different path* from the opencode deployment this repo also maintains
— different endpoint, different key, no proxy. See
[How this differs from the opencode path](#how-this-differs-from-the-opencode-path).

---

## Compliance notice

> The API URL you configure must belong to **`slac.stanford.edu`** or **GitHub
> Copilot**. Pointing Claude Code at any other endpoint is an unauthorized
> endpoint and may carry administrative or security consequences.

`https://ai-api.slac.stanford.edu` satisfies this. So does the Stanford gateway
(`aiapi-prod.stanford.edu`) used by opencode — but Claude Code does not need it.

---

## Prerequisites

| Requirement | Detail |
|---|---|
| Network | The gateway resolves and answers **only from the SLAC network or VPN**. On S3DF (`sdfiana025`, `sdfcron001`, batch nodes) it just works. From a laptop off-VPN it will not. |
| Key file | `/sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat` |
| Key permissions | `-rw-r-----  cwang31  ps-users`, 26 bytes, mode `0640` |
| Claude Code | **Nothing to install.** The binary is deployed for `ps-users` at `/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current` (2.1.235 as of 2026-08-28). `claude-lcls` runs that one and only that one. |

### Who can be onboarded

The key is group-readable by **`ps-users`**. That is the broad LCLS user group,
not the narrower `ps-data` staff group — so **anyone in `ps-users` can read the
key and use this setup without a permissions change**. Check yourself with:

```bash
id -nG | tr ' ' '\n' | grep -x ps-users && echo "you can read slac-key.dat"
```

If that prints nothing, ask for `ps-users` membership rather than asking for the
key to be copied. Never copy the key out of `dev/env/` into a home directory,
a repo, a ticket, or a chat message.

> **Measured note, 2026-08-26:** `key.dat` (the Stanford-gateway key used by
> opencode) is *also* `ps-users` / `0640` today — 25 bytes. Earlier internal
> notes describing it as `ps-data` are out of date; both keys currently have the
> same, broader audience. `tools/fix-key-perms.sh` re-asserts these modes.

---

## The shared binary

You do not install Claude Code to use `claude-lcls`. One binary is deployed for
the whole `ps-users` group:

```
/sdf/group/lcls/ds/dm/apps/dev/claude/bin/
├── versions/2.1.235          the binary, 0755 ps-users
├── current -> versions/2.1.235
└── VERSIONS.json             version, SHA-256, when and by whom
```

`claude-lcls` resolves `bin/current` **at call time**, so a version bump or a
rollback on the deploy side reaches you with nothing to re-run.

**It runs that binary and no other.** There is deliberately no fallback to
`command -v claude` or to `~/.local/share/claude/versions/*`. Two reasons: the
`~/.local/bin/claude` launcher shim has been observed vanishing from a home
directory, which used to leave `claude-lcls` installed and unable to start; and
a fallback meant two people could silently run two different Claude Code
versions against the same gateway.

Your own `claude` is untouched by all of this. It keeps using your own install
and your own `~/.claude/`. This setup never reads either one.

> **Escape hatch.** `CLAUDE_LCLS_BIN=/path/to/claude claude-lcls ...` overrides
> the shared binary for one command — useful for pinning an older version during
> an incident. It is opt-in: leaving it unset does *not* fall back to a personal
> install.

To publish or roll back a version, see `docs/claude-binary-publish.md`. Rolling
back is one command and needs no action from users.

### Where your files go

Everything `claude-lcls` writes lands in **your own** `$HOME/.claude-lcls/`.
Nothing is shared between users except the read-only binary and the read-only
skills. Measured on a config dir with real use behind it:

| Item | Path | Size |
|---|---|---|
| Transcripts | `~/.claude-lcls/projects/<slugified-cwd>/*.jsonl` | 2.4 MB |
| Plugins | `~/.claude-lcls/plugins/` | 6.4 MB |
| Sessions, history, shell snapshots, backups | `~/.claude-lcls/` | ~80 KB |
| Skill symlinks into the shared tree | `~/.claude-lcls/skills/` | 68 KB |
| **Total** | | **8.9 MB** |

Home directories carry a **30 GB per-user quota** (`df ~` reports 30 G while the
raw filesystem is 273 T). Two things follow.

**Not installing Claude Code personally saves you ~626 MB.** That is the
measured size of `~/.local/share/claude` on an account carrying two versioned
binaries. The shared copy costs you nothing.

**Transcripts are cleaned up on a bounded schedule.** Measured 2026-08-28: the
oldest surviving transcript in a config dir used since January was 25 days old,
consistent with Claude Code's default `cleanupPeriodDays` retention running
normally. Set `cleanupPeriodDays` in `~/.claude-lcls/settings.json` if you want a
different window; the installer does not set one, so you get the default.

---

## Quick setup

### 1. Create `~/.claude/settings.json`

Copy the template from this repo and lock it down:

```bash
mkdir -p ~/.claude
cp /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/settings.template.json \
   ~/.claude/settings.json
chmod og-rwx ~/.claude/settings.json
```

> **If you already have a working `~/.claude/settings.json`, stop here.** Do not
> overwrite it and do not merge the gateway blocks into it — that converts your
> existing install onto the gateway. Use the separate config directory described in
> [Already using Claude Code?](#already-using-claude-code-read-this-first) instead,
> and run both side by side.

### 2. Choose an auth method

The template ships with **`apiKeyHelper`** enabled, which reads the key from its
file at runtime. Nothing is pasted, nothing is duplicated:

```json
"apiKeyHelper": "cat /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat"
```

`apiKeyHelper` is a first-class Claude Code setting — the binary describes it as
*"Path to a script that outputs authentication values"*, and it accepts any shell
command whose stdout is the credential. Verified working end-to-end against this
gateway.

**If you prefer the pasted form instead**, delete the `apiKeyHelper` line and add
to the `env` block:

```json
"ANTHROPIC_AUTH_TOKEN": "<contents of slac-key.dat>"
```

### 3. Verify

```bash
claude -p "Reply with exactly: PONG" --model opus
# → PONG
```

See [Verification](#verification) for a fuller check that does not touch your
real config.

---

## Already using Claude Code? Read this first

Most people being onboarded here **already have a working Claude Code setup** on a
personal Anthropic subscription. For them, the [Quick setup](#quick-setup) above
is the wrong instructions: writing the gateway template into `~/.claude/settings.json`
switches that install wholesale onto the SLAC gateway, and merging the two configs
leaves one install whose model aliases and credentials depend on which block won.

You do not have to choose. **Run both, side by side, in separate config
directories.** Pick your path:

| Your situation | Do this |
|---|---|
| No existing Claude Code config, or happy to move entirely to the gateway | [Quick setup](#quick-setup) — write `~/.claude/settings.json` |
| Existing personal-subscription setup you want to keep | **This section** — a second config dir plus a `claude-lcls` shell function |

---

### The mechanism: `CLAUDE_CONFIG_DIR`

`CLAUDE_CONFIG_DIR` relocates the **entire** Claude Code state directory, not just
`settings.json`. Verified on 2.1.235 (see [What `CLAUDE_CONFIG_DIR` actually
moves](#what-claude_config_dir-actually-moves)): point it at a directory of its own
and that run reads and writes only there, leaving your personal config untouched.

Two requirements:

- **It must be writable.** Claude Code stores `.claude.json`, session transcripts,
  per-project state and backups inside it. It therefore cannot be the shared
  read-only tree under `dev/`; it has to be a per-user directory.
- **Do not also override `HOME`.** See
  [Do not use `HOME` for isolation](#do-not-use-home-for-isolation).

### Setup

**1. Create the SLAC config directory and drop the template in it:**

```bash
mkdir -p ~/.claude-lcls
cp /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/settings.template.json \
   ~/.claude-lcls/settings.json
chmod 700 ~/.claude-lcls
chmod og-rwx ~/.claude-lcls/settings.json
```

Your existing `~/.claude/` is not read, not written, and not modified.

**2. Add a launcher function to your shell rc** (`~/.bashrc`, `~/.zshrc`):

```bash
claude-lcls() {
  local _bin="${CLAUDE_LCLS_BIN:-/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current}"
  if [ ! -x "$_bin" ]; then
    echo "claude-lcls: shared Claude Code binary is not runnable: $_bin" >&2
    echo "claude-lcls: check you are still in ps-users -- id -nG" >&2
    return 127
  fi
  local _rest=":$PATH:"
  while :; do
    case "$_rest" in
      *":/sdf/group/lcls/ds/dm/apps/dev/bin:"*)
        _rest="${_rest%%:/sdf/group/lcls/ds/dm/apps/dev/bin:*}:${_rest#*:/sdf/group/lcls/ds/dm/apps/dev/bin:}" ;;
      *) break ;;
    esac
  done
  _rest="${_rest#:}"; _rest="${_rest%:}"
  PATH="/sdf/group/lcls/ds/dm/apps/dev/bin${_rest:+:$_rest}" \
    CLAUDE_CONFIG_DIR="$HOME/.claude-lcls" "$_bin" "$@"
}
```

This is what `install-claude-lcls.sh` writes for you; the manual form is here
only for people who would rather not run the installer.

Three details are deliberate. `bin/current` is resolved **at call time**, not
frozen into the function, so a version bump or rollback on the deploy side
reaches you with nothing to re-run. There is no fallback to `command claude` or
to `~/.local/share/claude/versions/*` — see
[The shared binary](#the-shared-binary) for why. And the shared tools directory
goes **first** on `PATH` — see below.

### Shared tools on `PATH` (this is where `uv` comes from)

Many deployed skills — `confluence-search`, `jira-search`, `elog-search`,
`ask-slac-ai-tools` and others — shell out to a bare `uv run` on a PEP 723
inline-metadata script, and agents reach for `uv run` in their own work too.
Nothing on S3DF puts `uv` on `PATH` by default.

`claude-lcls` puts `/sdf/group/lcls/ds/dm/apps/dev/bin` **first** on `PATH` for
its own sessions. That is where the team `uv` lives (0.9.8, world-executable),
so every `uv` a session runs is that one, whether or not you installed your own.

**Prepended, not appended.** The first version appended, so a personal `uv`
kept winning. That meant a skill ran on whatever `uv` a given user happened to
have, which is the variation a shared deployment exists to remove — the same
reason `claude-lcls` runs only the shared Claude binary. The skills' own
`env.sh` files also prepend this directory, but only when an agent remembers to
source one first, and recorded sessions show bare `uv run` calls that did not.

Measured on Claude Code 2.1.267: with the directory appended, the Bash tool
resolved `~/.local/bin/uv`; with it prepended, it resolved the shared `uv` —
including when `~/.bashrc` prepends `~/.local/bin` unconditionally, because the
Bash tool keeps the `PATH` that `claude-lcls` starts with.

The `PATH` change is scoped to the `claude-lcls` command. Your interactive shell
is not modified, so outside `claude-lcls` your own `uv` still wins. Any copy of
the directory already on `PATH` is removed before it is prepended, so nesting
`claude-lcls` keeps exactly one entry. The installer's verification step
reports which `uv` a session will find.

`UV_PYTHON_INSTALL_DIR` is deliberately **not** set by the launcher. Only the
deployment owner can write the shared Python directory
(`/sdf/group/lcls/ds/dm/apps/dev/python`), so pointing every `uv` at it would
turn a request for a Python version it lacks into a hard `Permission denied`
instead of a download into your home. Skills that need the shared Pythons set
it themselves, together with a per-user `UV_CACHE_DIR` (`/tmp/uv-cache-$USER`),
in their `env.sh`, so nothing writes to a shared cache.

**3. Use them independently:**

```bash
claude       # your personal subscription, ~/.claude, unchanged
claude-lcls  # the SLAC gateway, ~/.claude-lcls
```

Two sets of sessions, two sets of project histories, two sets of settings. No
interference in either direction.

### What `CLAUDE_CONFIG_DIR` actually moves

**Measured 2026-08-26, Claude Code 2.1.235.** A throwaway config dir containing only
a `settings.json` was used for one real gateway completion
(`-p 'Reply with exactly: OK' --model us.anthropic.claude-haiku-4-5-...`, which
returned `OK`). Afterwards the directory contained:

```
-rw-------  .claude.json      <-- relocated
drwxr-xr-x  projects/         <-- relocated
drwx------  sessions/         <-- relocated
drwxr-xr-x  backups/          <-- relocated
-rw-r-----  settings.json
```

and `md5sum ~/.claude.json` was **byte-identical before and after the run**
(`954d0fac04aae0d498698961bd12dd90` both times). Nothing in the real `~/.claude/`
was touched.

> **Correction to an older internal doc.** `docs/claude-code-as-harness.md`
> (2026-06-26) states in two places — its comparison table and its "Gotchas"
> section — that `.claude.json` (OAuth/MCP state) is **not** relocated by
> `CLAUDE_CONFIG_DIR` and must be made separately writable. That was true of an
> earlier release; **it is not true of 2.1.235**, as measured above. That document
> is stale on this point and needs reconciling — its container recipe carries extra
> writable-path plumbing for `~/.claude.json` that is no longer required. This guide
> is the current source of truth for the isolation behaviour; nothing in
> `claude-code-as-harness.md` has been edited here.

Note that `--version` alone creates nothing — the config dir is populated on the
first run that actually starts a session. Do not conclude from an empty directory
that the variable was ignored.

### Do not use `HOME` for isolation

A tempting shortcut is `HOME=/some/dir claude ...`. **Do not.**

`CLAUDE_CONFIG_DIR` alone is sufficient for isolation. Adding `HOME` buys nothing
and costs you your shell environment, your SSH keys, your Kerberos cache and
anything else keyed off the home directory.

> **Updated 2026-08-28.** This section used to give a second, sharper reason: the
> `claude` launcher shim resolved its real binary from
> `$HOME/.local/share/claude/versions/<ver>`, so overriding `HOME` made the
> launch fail outright. That no longer applies to `claude-lcls`, which invokes
> the shared binary by absolute path and is indifferent to `HOME`. The advice
> stands; only the mechanism changed. It still applies verbatim to your
> *personal* `claude`, which is still launched through that shim.

### Shared skills

The deploy target now **exists**. Seventeen team skills live read-only under
`/sdf/group/lcls/ds/dm/apps/dev/claude/skills/`:

```
ask-ami                    ask-nersc          ask-tiled
askcode                    ask-olcf           confluence-search
ask-epics                  ask-s3df           cuda-docs
ask-lcls2                  ask-slac-ai-tools  docs-search
ask-slurm-s3df             ask-smalldata      elog-search
experimental-hutch-python  xpm-seq
```

**How discovery works.** Claude Code loads skills from
`$CLAUDE_CONFIG_DIR/skills/`, and `CLAUDE_CONFIG_DIR` must be **writable** — it
is where Claude Code keeps its own state. So it cannot simply point at the
read-only shared tree. The working pattern is a writable `~/.claude-lcls/` whose
`skills/` directory holds **one symlink per deployed skill**, each pointing into
the shared tree.

`install-claude-lcls.sh` now does this for you, and re-running it re-links
idempotently. The by-hand equivalent:

```bash
mkdir -p ~/.claude-lcls/skills
for s in /sdf/group/lcls/ds/dm/apps/dev/claude/skills/*/; do
  ln -sfn "${s%/}" ~/.claude-lcls/skills/"$(basename "$s")"
done
```

> **⚠️ Symlink each ENTRY — never the whole `skills` directory.**
> If `~/.claude-lcls/skills` is itself a symlink to the shared directory, a later
> `mkdir -p ~/.claude-lcls/skills/whatever` **follows the link** and creates a
> directory *inside the live read-only production tree*. This has actually
> happened once and had to be cleaned up by hand. One link per skill entry keeps
> every write on your side of the boundary.

**There is no `commands` directory.** `dev/claude/` contains **only** `skills/`.
Do **not** create a `~/.claude-lcls/commands` symlink — it would dangle.

**Verify.** First, the links themselves — 17 of them:

```bash
ls -l ~/.claude-lcls/skills/
```

Then ask Claude Code what it can actually see, **from a directory outside this
repo** (a cwd inside the repo lets `CLAUDE.md` leak context into the answer and
invalidates the check):

```bash
cd /tmp && claude-lcls -p \
  "List the exact names of every Skill available to you, one per line, nothing else."
```

The team skill names should appear alongside Claude Code's bundled ones.

Use `claude-lcls` here, not a bare `claude`. The function sets
`CLAUDE_CONFIG_DIR` for you and runs the shared team binary by absolute path, so
it works whether or not you have a personal `claude` on `PATH`.
`install-claude-lcls.sh` resolves the same binary in its preflight and in its own
verification step.

The group ownership the shared target carries is settled in
[`deploy-permissions.md`](deploy-permissions.md).

---

## Can `ANTHROPIC_AUTH_TOKEN` be sourced from a file?

**Not directly — but you do not need it to be.**

- `ANTHROPIC_AUTH_TOKEN` in `settings.json` is a **literal string only**. Claude
  Code does not expand `{file:...}`, `$(...)`, or `$VAR` inside `env` values.
  (opencode's `opencode.json` *does* support `{file:...}` — that syntax is an
  opencode feature and does not carry over.)
- **`apiKeyHelper` is the file-sourced equivalent** and is the recommended form
  for a shared team deployment. It runs a command and uses its stdout as the
  credential, so `cat .../slac-key.dat` gives you exactly "read the key from its
  path at runtime".
- You can also export `ANTHROPIC_AUTH_TOKEN="$(cat .../slac-key.dat)"` in your
  shell rc instead of putting it in `settings.json` — this keeps the secret out
  of any file, but leaks it into your process environment (`/proc/<pid>/environ`,
  `ps -E` on some systems) and into shell history if typed interactively.

**Why this matters for a team deployment.** The naive guide asks every user to
paste the shared key into their own home directory. That creates N copies of one
secret across N home directories with N different permission histories, and a
rotation then requires chasing all N. `apiKeyHelper` keeps exactly one copy — the
one in `dev/env/`, already correctly owned and grouped — and rotation is a single
file write. **Use `apiKeyHelper` unless you have a specific reason not to.**

---

## Model IDs

Do not guess these. The gateway exposes a listing endpoint; query it:

```bash
K=$(cat /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat)
curl -s -H "x-api-key: $K" https://ai-api.slac.stanford.edu/v1/models \
  | python3 -c 'import json,sys; [print(m["id"]) for m in json.load(sys.stdin)["data"]]'
```

Anthropic models served as of **2026-09-19** (`GET /v1/models` → `200`):

| Model ID | Max input | Max output | Verified |
|---|---:|---:|---|
| `us.anthropic.claude-fable-5-1` | 1,000,000 | 128,000 | listed + completion via `--model fable` |
| `us.anthropic.claude-opus-5-5` | 1,000,000 ¹ | 128,000 ¹ | added 2026-10-07; listed + `POST /v1/messages` → `200`, 215k-token request → `200` |
| `us.anthropic.claude-opus-5` | 1,000,000 | 128,000 | listed + `POST /v1/messages` → `200` |
| `us.anthropic.claude-opus-4-8` | 1,000,000 | 128,000 | listed |
| `us.anthropic.claude-opus-4-7` | 1,000,000 | 128,000 | listed |
| `us.anthropic.claude-opus-4-6-v1` | 1,000,000 | 128,000 | listed |
| `us.anthropic.claude-sonnet-5` | 1,000,000 | 128,000 | listed + `POST /v1/messages` → `200` |
| `us.anthropic.claude-sonnet-4-6` | 1,000,000 | 64,000 | listed |
| `us.anthropic.claude-haiku-4-5-20251001-v1:0` | 200,000 | 64,000 | listed + `POST /v1/messages` → `200` |

¹ Anthropic's figures. The listing itself says 200,000 / 64,000 for Opus 5.5, but
that metadata is stale: a 215k-token request succeeded. Opus 5.5 also gets a
five-minute prompt cache only, even with `promptCacheTtl: "1h"`. Both are
gateway-side; see `docs/claude-binary-publish.md` § 2.1.285.

The gateway also serves OpenAI, Gemma, Nova, Llama, and Stability models — see
the listing. Those are not usable from Claude Code, which speaks the Anthropic
Messages API.

**Claude 5 is available, including Fable 5.1.** The previously documented pins
(Sonnet 4.6, Opus 4.8) still work but are a generation behind; the template uses
Opus 5.5, Sonnet 5, and Fable 5.1. Opus 5.5 needs Claude Code 2.1.285+ to be
recognized; 2.1.267 runs it but caps output at 32,000 tokens. Opus 5 stays
reachable with `claude-lcls --model "us.anthropic.claude-opus-5[1m]"`.

Fable 5.1 reaches the picker through `ANTHROPIC_DEFAULT_FABLE_MODEL`, which also
makes `--model best` resolve to it (`best` means "Fable where available,
otherwise Opus"). Anthropic's docs say the `fable` alias requires Claude Code
2.1.257+, but **2.1.235 resolved both `fable` and `best` to
`us.anthropic.claude-fable-5-1` once the var was set** — measured 2026-09-19 with
`--output-format json`, reading the `modelUsage` key back.

### The `[1m]` suffix

`[1m]` is a **Claude Code client-side alias suffix**, not part of the model id.

- Sending `"model": "us.anthropic.claude-opus-5[1m]"` to `/v1/messages` with raw
  `curl` returns **`400 Invalid model name passed in
  model=us.anthropic.claude-opus-5[1m]`**.
- Putting that same string in `ANTHROPIC_DEFAULT_OPUS_MODEL` and running
  `claude -p ... --model opus` **succeeds** — Claude Code strips the suffix
  before it hits the wire.
- `claude --model "opus[1m]"` also succeeds.

So the template's `[1m]`-suffixed pins are correct *for settings.json* and would
be wrong in a hand-rolled curl.

**The suffix is not belt-and-braces — it is load-bearing.** Measured 2026-09-19 on
2.1.235 through this gateway, reading `modelUsage[...].contextWindow` back from
`--output-format json`:

| Pin | Reported context window |
|---|---:|
| `us.anthropic.claude-sonnet-5` | 200,000 |
| `us.anthropic.claude-sonnet-5[1m]` | 1,000,000 |
| `us.anthropic.claude-fable-5-1` | 200,000 |
| `us.anthropic.claude-fable-5-1[1m]` | 1,000,000 |
| `us.anthropic.claude-opus-5[1m]` | 1,000,000 |

Both forms return a completion, so the un-suffixed pin fails silently by running
at a fifth of the advertised window. This supersedes the earlier note that the
suffix might be a no-op: it is not.

**Re-measured on 2.1.267 after the pin bump, and the suffix is still required.**
Anthropic's docs say Sonnet 5 carries the 1M window natively with no `[1m]`
variant to select; through this gateway that does not hold. Plain
`us.anthropic.claude-sonnet-5`, `...opus-5` and `...fable-5-1` each report
200,000 on 2.1.267, and all three report 1,000,000 with the suffix. Keep
re-measuring on future bumps — this is observed gateway behaviour, not a
documented contract.

**Opus 5.5 on 2.1.285 is the first pin that does not need the suffix.** Plain
`us.anthropic.claude-opus-5-5` reports 1,000,000, the same as the suffixed form.
The template keeps `[1m]` anyway, so a rollback to 2.1.267 keeps the 1M window.

`--model best` resolves to `us.anthropic.claude-fable-5-1[1m]` at 1,000,000.
`haiku` reports 200,000, which is Haiku 4.5's native size on the gateway rather
than a missing suffix.

`max_output_tokens` stays at 64,000 in every case even though the gateway
advertises 128,000. `CLAUDE_CODE_MAX_OUTPUT_TOKENS` is the likely lever; untested.

### Never carry `[1m]` into `opencode.json`

The suffix is a Claude Code client-side convention. opencode does **not** strip
it, so `slac/us.anthropic.claude-opus-5[1m]` reaches the gateway verbatim and
returns `400 Invalid model name passed in model=us.anthropic.claude-opus-5[1m]`.
Use the plain id in `opencode.json`; it already advertises 1M input / 128k output,
recorded there in each model's `limit` block. Copying an env var out of
`settings.template.json` into `opencode.json` is the specific mistake to avoid.

### All four `ANTHROPIC_DEFAULT_*_MODEL` vars are required

Omitting one is not harmless. With `ANTHROPIC_DEFAULT_HAIKU_MODEL` unset,
`claude --model haiku` resolves to Anthropic's public id
`claude-haiku-4-5-20251001` and the gateway rejects it:

```
API Error: 400 ... Invalid model name passed in model=claude-haiku-4-5-20251001
```

Haiku is what Claude Code uses for background work (titles, summaries), so an
unset haiku var produces intermittent errors even when your main model works.

`ANTHROPIC_DEFAULT_FABLE_MODEL` fails differently: rather than erroring, `/model
fable` and `/model best` simply do not reach Fable 5.1, so you silently keep
whatever the previous alias resolved to.

### Re-running the installer keeps your own keys

`install-claude-lcls.sh` **merges** this template into an existing
`~/.claude-lcls/settings.json` rather than replacing it. Keys the template
defines are updated -- that is how a new model pin or cache setting reaches
everyone. Keys it does not define survive, including nested ones, so a personal
`theme`, `model`, `effortLevel`, or an extra `env` var of your own is not lost.
The run prints what it kept:

```
  ok  merged the shared template into ~/.claude-lcls/settings.json (mode 600)
  ok  kept your local-only key(s): env.MY_OWN_VAR model effortLevel theme
  ok  previous copy: ~/.claude-lcls/settings.json.bak-20260920103000
```

A backup is written only when the merge actually changes something, so
re-running on an up-to-date file leaves no litter. `--reset` opts out and
rebuilds the canonical file, discarding local-only keys (after a backup).

Three consequences worth knowing:

- **`theme`, `model` and `effortLevel` are deliberately absent from the
  template.** They are personal choices, and for some people the theme is an
  accessibility requirement rather than a preference. Do not add them: a shared
  default would silently override every user on their next re-run.
- **Removing a key from the template no longer removes it from existing users.**
  Retiring a setting takes an explicit prune or a `--reset`, not just a deletion.
- **If your settings.json is not valid JSON, the merge refuses and changes
  nothing**, telling you where the parse failed. Fix it, or use `--reset`.

The merge runs on the shared uv-managed Python
(`/sdf/group/lcls/ds/dm/apps/dev/bin/uv run --python 3.11`, resolved against
`/sdf/group/lcls/ds/dm/apps/dev/python` so nothing is downloaded), the same
centralized interpreter the deployed skills use. It falls back to a system
`python3`, and if no interpreter can parse JSON it writes the template wholesale
and says so rather than refusing to install.

### One-hour prompt cache

`promptCacheTtl: "1h"` keeps the main conversation's cached prefix alive through
an hour-long gap instead of five minutes, which is what an idle-then-resume
session wants. One-hour cache writes bill at 2x base input against 1.25x for the
five-minute default, so it costs more on short bursts that never idle past five
minutes and saves on sessions left and picked back up.

It covers the **main conversation only**. Subagents, compaction, and session
titles keep the five-minute default, because `subagentPromptCacheTtl` is left
unset deliberately. The older `ENABLE_PROMPT_CACHING_1H=1` env var applies the
hour to both buckets at once.

**Version floor: 2.1.242.** A string scan of 2.1.235 finds zero occurrences of
`promptCacheTtl`, `subagentPromptCacheTtl`, or `CLAUDE_CODE_PROMPT_CACHE_TTL`;
2.1.267 has all three. Since Claude Code ignores unknown settings keys in
silence, writing this key on 2.1.235 reads as working and does nothing. The
shared pin lives in `tools/claude-binary/env.sh` and moved to 2.1.267 on
2026-09-19 for exactly this reason.

**Measured working on 2.1.267 through this gateway**, with the `sonnet`, `opus`
and `fable` aliases returning 50,886 / 39,032 / 40,240 `ephemeral_1h_input_tokens`
and zero `ephemeral_5m_input_tokens`. The `anthropic-beta` header survives the
gateway, and `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS: "1"` does not suppress it —
that flag had been the main suspect.

Confirm the hour actually reaches the gateway:

```bash
claude -p "hello" --output-format json | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["usage"]["cache_creation"])'
```

A non-zero `ephemeral_1h_input_tokens` is success; tokens landing under
`ephemeral_5m_input_tokens` mean the hour did not take. Part of the one-hour
request rides in the `anthropic-beta` header, so a gateway that rewrites or drops
that header leaves you at five minutes with no error. The
`CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS: "1"` in this template is a second
suspect worth toggling before blaming the gateway.

---

## Settings reference

### `skipWebFetchPreflight` is a **top-level** key

```json
{ "skipWebFetchPreflight": true }
```

Some older internal notes nest it as `"settings": { "skipWebFetchPreflight": true }`.
That is wrong — there is no `settings` object in the schema, and a nested value is
silently ignored. In the binary's settings schema `skipWebFetchPreflight` sits
flat alongside `outputStyle`, `language`, and `sandbox`, described as *"Skip the
WebFetch blocklist check for enterprise environments"*.

### Traffic reduction

```json
"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
```

This single variable is equivalent to enabling all four of:

- `DISABLE_AUTOUPDATER`
- `DISABLE_FEEDBACK_COMMAND`
- `DISABLE_ERROR_REPORTING`
- `DISABLE_TELEMETRY`

Set it. On a shared facility deployment you do not want the autoupdater racing
against a centrally managed version, and you do not want error reports leaving
the site.

```json
"CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1"
```

Keeps Claude Code from negotiating beta features the gateway may not proxy.

### Sensitive-information options

Add either of these to the `env` block if your work is sensitive. They change how
Claude Code **records, persists, or reuses information across sessions**:

| Variable | Effect |
|---|---|
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` | Disables automatic memory capture — Claude Code will not write learned facts about your work into persistent memory files. |
| `CLAUDE_CODE_SIMPLE=1` | Reduced-surface mode; fewer session-persisting features. |

Both are recognised settings in 2.1.235. Consider them mandatory for anything
touching proprietary, embargoed, or export-controlled work.

### Attribution

```json
"attribution": {
  "commit": "Generated with AI\n\nCo-Authored-By: SLAC AI",
  "pr": ""
}
```

`commit` is the trailer block appended to git commits; `pr` is the pull-request
body attribution — an **empty string hides it entirely**. Both are real settings
(*"Customize attribution text for commits and PRs. Each field defaults to the
standard Claude Code attribution if not set."*).

---

## How this differs from the opencode path

| | opencode (this repo's main deployment) | Claude Code (this guide) |
|---|---|---|
| Endpoint | `https://aiapi-prod.stanford.edu/v1` (Stanford, OpenAI-compatible) | `https://ai-api.slac.stanford.edu` (SLAC, Anthropic Messages) |
| Key file | `dev/env/key.dat` | `dev/env/slac-key.dat` |
| Proxy | `proxy/` on `sdfcron001:4000` injects the key so users never read it | **Not needed.** Claude Code talks to the SLAC gateway directly. |
| Config | `opencode.json`, supports `{file:...}` key expansion | `~/.claude/settings.json`, uses `apiKeyHelper` instead |
| Base URL trailing `/v1` | **Include it** — `.../v1` | **Omit it** — Claude Code appends `/v1/messages` itself |

The `proxy/` route documented in [`../proxy/README.md`](../proxy/README.md) *can*
front Claude Code (`ANTHROPIC_BASE_URL=http://sdfcron001:4000`), but that path
goes to the Stanford gateway with `key.dat`. **If you want the SLAC gateway, skip
the proxy** — it adds a hop, a second secret (the proxy key), and a single point
of failure on `sdfcron001` for no benefit, since `slac-key.dat` is already
readable by everyone in `ps-users`.

The proxy remains the right answer for users who must **not** be able to read a
key at all.

---

## Verification

### A. Gateway reachability (no Claude Code needed)

```bash
K=$(cat /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat)
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "x-api-key: $K" https://ai-api.slac.stanford.edu/v1/models
# → 200
```

`000` or a hang means you are off the SLAC network/VPN. `401`/`403` means the key
is not readable or not valid.

### B. One real completion

```bash
K=$(cat /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat)
curl -s -X POST https://ai-api.slac.stanford.edu/v1/messages \
  -H "x-api-key: $K" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"us.anthropic.claude-opus-5","max_tokens":1,
       "messages":[{"role":"user","content":"hi"}]}' | head -c 200
```

A `200` body echoing `"model":"us.anthropic.claude-opus-5"` is success.
`max_tokens:1` keeps the test essentially free — this is a shared, billed key.

### C. Claude Code end-to-end, **without touching your real config**

```bash
D=$(mktemp -d)
cp <this-repo>/claude/settings.template.json "$D/settings.json"
CLAUDE_CONFIG_DIR="$D" claude -p "Reply with exactly: PONG" --model opus
# → PONG
rm -rf "$D"
```

`CLAUDE_CONFIG_DIR` **on its own** is what keeps the throwaway run from reading or
writing your real config — it relocates `settings.json`, `.claude.json`,
`sessions/`, `projects/` and `backups/` together. Verified on 2.1.235 by
md5-checking `~/.claude.json` before and after a live run; see
[What `CLAUDE_CONFIG_DIR` actually moves](#what-claude_config_dir-actually-moves).

**Do not add `HOME="$D"`.** An earlier version of this guide did; it breaks the
`claude` launcher, which resolves its versioned binary from a path under `$HOME`.
See [Do not use `HOME` for isolation](#do-not-use-home-for-isolation).

Repeat with `--model sonnet` and `--model haiku` to confirm all three aliases
resolve.

### Troubleshooting

| Symptom | Cause |
|---|---|
| `Invalid model name passed in model=claude-...` (no `us.anthropic.` prefix) | An `ANTHROPIC_DEFAULT_*_MODEL` var is unset; Claude Code fell back to a public Anthropic id. |
| `Invalid model name ...[1m]` from curl | You put a Claude Code alias suffix in a raw API call. Drop `[1m]`. |
| Hang / connection refused | Off the SLAC network or VPN. |
| `cat: ...slac-key.dat: Permission denied` | Not in `ps-users`. |
| `claude-lcls: shared Claude Code binary is not runnable: ...` | You are probably no longer in `ps-users` — check `id -nG`. Test the binary directly: `/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current --version`. Do **not** fix this by installing Claude Code into your home directory; `claude-lcls` does not use a personal install, so it would change nothing. |
| `claude: command not found` | That is your *personal* `claude`, which this setup does not provide and does not touch. `claude-lcls` is unaffected — it runs the shared binary by absolute path. |
| Everyone suddenly on a different Claude Code version | Expected after a deploy-side `activate`. `bin/current` is resolved at call time by design. `readlink /sdf/group/lcls/ds/dm/apps/dev/claude/bin/current` shows which version is live; `VERSIONS.json` beside it records when it changed and by whom. |
| `claude-lcls` picks up your personal settings | The function is exporting nothing — check it sets `CLAUDE_CONFIG_DIR` *on the command*, and that `~/.claude-lcls/settings.json` exists. A config dir with no `settings.json` falls back to defaults, not to `~/.claude/`. |
| `max_tokens must be greater than thinking.budget_tokens` | The gateway applies an extended-thinking budget by default; `max_tokens: 1` is too small for some models. Raise it (e.g. 1025) or disable thinking. |

---

## Security rules

- **Never** commit a key, a key prefix, or a key length into this repo. The
  template carries a placeholder or an `apiKeyHelper` path — never a literal.
- `chmod og-rwx ~/.claude/settings.json` if you chose the pasted form.
- Do not copy `slac-key.dat` anywhere. Read it in place.
- Do not echo it into logs. In shell snippets, load it into a variable and pass
  it only via a header; never `echo "$K"`.
- If a key is exposed, say so immediately — rotation is cheap, a silent leak is
  not.
