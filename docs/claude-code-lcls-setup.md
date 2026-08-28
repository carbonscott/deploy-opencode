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
  local _path="$PATH"
  case ":$_path:" in
    *":/sdf/group/lcls/ds/dm/apps/dev/bin:"*) ;;
    *) _path="$_path:/sdf/group/lcls/ds/dm/apps/dev/bin" ;;
  esac
  PATH="$_path" CLAUDE_CONFIG_DIR="$HOME/.claude-lcls" "$_bin" "$@"
}
```

This is what `install-claude-lcls.sh` writes for you; the manual form is here
only for people who would rather not run the installer.

Three details are deliberate. `bin/current` is resolved **at call time**, not
frozen into the function, so a version bump or rollback on the deploy side
reaches you with nothing to re-run. There is no fallback to `command claude` or
to `~/.local/share/claude/versions/*` — see
[The shared binary](#the-shared-binary) for why. And the shared tools directory
is **appended** to `PATH` — see below.

### Shared tools on `PATH` (this is where `uv` comes from)

Several deployed skills — `confluence-search`, `ask-slac-ai-tools` — shell out to
a bare `uv run` on a PEP 723 inline-metadata script. Nothing on S3DF puts `uv` on
`PATH` by default, and no skill's `env.sh` adds it: they only add their own
`bin/`. So whether those skills worked came down to whether you happened to have
installed `uv` yourself.

`claude-lcls` now appends `/sdf/group/lcls/ds/dm/apps/dev/bin` to `PATH` for its
own sessions, which is where the team `uv` lives (0.9.8, world-executable).

**Appended, not prepended.** If you already have your own `uv`, it still wins.
This only fills a gap; it never overrides a choice you made. Verified both ways:
from an environment with no `uv` at all, `claude-lcls` resolves
`/sdf/group/lcls/ds/dm/apps/dev/bin/uv` and runs a PEP 723 script successfully;
with a `uv` earlier on `PATH`, that one is used instead.

The `PATH` change is scoped to the `claude-lcls` command. Your interactive shell
is not modified, and the guard means nesting `claude-lcls` does not repeat the
entry.

Skills that use `uv` set their own per-user `UV_CACHE_DIR` (`/tmp/uv-cache-$USER`)
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

Anthropic models served as of **2026-08-26** (`GET /v1/models` → `200`):

| Model ID | Max input | Max output | Verified |
|---|---:|---:|---|
| `us.anthropic.claude-opus-5` | 1,000,000 | 128,000 | listed + `POST /v1/messages` → `200` |
| `us.anthropic.claude-opus-4-8` | 1,000,000 | 128,000 | listed |
| `us.anthropic.claude-opus-4-7` | 1,000,000 | 128,000 | listed |
| `us.anthropic.claude-opus-4-6-v1` | 1,000,000 | 128,000 | listed |
| `us.anthropic.claude-sonnet-5` | 1,000,000 | 128,000 | listed + `POST /v1/messages` → `200` |
| `us.anthropic.claude-sonnet-4-6` | 1,000,000 | 64,000 | listed |
| `us.anthropic.claude-haiku-4-5-20251001-v1:0` | 200,000 | 64,000 | listed + `POST /v1/messages` → `200` |

The gateway also serves OpenAI, Gemma, Nova, Llama, and Stability models — see
the listing. Those are not usable from Claude Code, which speaks the Anthropic
Messages API.

**Claude 5 is available.** The previously documented pins (Sonnet 4.6, Opus 4.8)
still work but are a generation behind; the template uses Opus 5 and Sonnet 5.

### The `[1m]` suffix

`[1m]` is a **Claude Code client-side alias suffix**, not part of the model id.

- Sending `"model": "us.anthropic.claude-opus-5[1m]"` to `/v1/messages` with raw
  `curl` returns **`400 Invalid model name passed in
  model=us.anthropic.claude-opus-5[1m]`**.
- Putting that same string in `ANTHROPIC_DEFAULT_OPUS_MODEL` and running
  `claude -p ... --model opus` **succeeds** — Claude Code strips the suffix
  before it hits the wire.
- `claude --model "opus[1m]"` also succeeds.

So the template's `us.anthropic.claude-opus-5[1m]` is correct *for settings.json*
and would be wrong in a hand-rolled curl. Note the gateway already advertises
`max_input_tokens: 1000000` for `us.anthropic.claude-opus-5` regardless, so the
suffix is belt-and-braces. **Not independently verified:** whether the suffix
changes the effective context window when going through this gateway, as opposed
to being a no-op the gateway ignores.

### All three `ANTHROPIC_DEFAULT_*_MODEL` vars are required

Omitting one is not harmless. With `ANTHROPIC_DEFAULT_HAIKU_MODEL` unset,
`claude --model haiku` resolves to Anthropic's public id
`claude-haiku-4-5-20251001` and the gateway rejects it:

```
API Error: 400 ... Invalid model name passed in model=claude-haiku-4-5-20251001
```

Haiku is what Claude Code uses for background work (titles, summaries), so an
unset haiku var produces intermittent errors even when your main model works.

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
