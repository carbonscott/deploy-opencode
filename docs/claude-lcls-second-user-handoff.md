# claude-lcls: second-user handoff

**Status:** procedure, not a result. Everything below was measured on `sdfiana025`
on 2026-08-27 **as user `cwang31`**, and every command in it was re-run and
re-checked independently on the same day. `cwang31` is a member of `gu`, `ps-data` and
`ps-users`, so every permission check in this document passed for the wrong
reason: `cwang31` owns the files. The point of the exercise is to run it as
somebody who is in `ps-users` and **not** in `ps-data`, because that is the only
principal for which the interesting checks can actually fail.

---

## 1. Who this is for, and what it proves

You are the second user. You are in `ps-users`. You are (probably) not in
`ps-data`, and you do not own anything under
`/sdf/group/lcls/ds/dm/apps/dev/`.

`install-claude-lcls.sh` installs a `claude-lcls` shell function that runs
Claude Code against the SLAC AI Gateway using a shared team key, leaving your
existing `claude` setup untouched. It has only ever been run by `cwang31`.
Running it as you is the only thing that really tests two claims:

1. **The key-file ACL works as designed.** Two independent permissions have
   to combine, and it is worth being exact about which does what. The key lives
   in `/sdf/group/lcls/ds/dm/apps/dev/env/`, a directory owned by `cwang31`,
   group `ps-data`, mode `2770`, `other::---`, carrying exactly one named-group
   ACL entry: `group:ps-users:--x`. Execute without read means *traverse but do
   not list* — that, and only that, is what the ACL gives you. The key file
   itself is a different object: owner `cwang31`, but group-owned by
   **`ps-users`**, mode `640`, and its own ACL names no group beyond the owning
   one. Your read comes from plain group ownership there (`group::r-x` capped
   by `mask::r--`, so effectively `r--`). So a `ps-users` member is expected to
   be able to read the key **by its exact full path** — traversal from the
   directory's ACL, read from the file's group — while being unable to `ls` the
   directory that contains it. That asymmetry has never been observed from the
   outside; `cwang31` is in `ps-data` and can do both.
2. **The deployed skills tree is group-readable.**
   `/sdf/group/lcls/ds/dm/apps/dev/claude/skills` is owned by `cwang31`, group
   `ps-users`, mode `2750` — so `ps-users` should get read+traverse on the tree
   and on all 17 skills inside it. Again, never verified from a non-owner
   account.

**Prerequisites**

* Membership in the `ps-users` group (gid 10000).
* A shell on an S3DF interactive node. The reference host for everything below
  is `sdfiana025`.
* **No Claude Code install.** Since 2026-08-28 the binary is deployed for
  `ps-users` and `claude-lcls` runs that one. If you already have your own, it
  is left alone and never read.
* The SLAC network or the SLAC VPN. The gateway `https://ai-api.slac.stanford.edu`
  does not answer from outside it, and the installer refuses to proceed when it
  cannot reach it.

**Please do not** copy the key anywhere, paste it into a ticket, or `cat` it to
a terminal you are sharing. Every check in this document is deliberately written
to avoid printing it.

---

## 2. Pre-flight — run these BEFORE the installer

Five checks. Run them in order and keep the output; section 6 asks you to send
most of it back.

### 2.1 Confirm `ps-users` membership

```bash
id -nG | tr ' ' '\n' | grep -x ps-users
```

Expected output:

```
ps-users
```

Nothing at all (and exit status 1) means you are not in the group, and the rest
of this document will not work. Ask for `ps-users` membership; do not ask anyone
to hand you a copy of the key.

Full group list, worth capturing either way:

```bash
id -nG
```

For reference, this is what `cwang31` prints — you should print something
different, and specifically you should **not** have `ps-data`:

```
gu ps-data ps-users
```

### 2.2 Read the key by exact path, and fail to list its directory

These two commands are a matched pair. **The second one is supposed to fail.**
Its failure is the feature being tested — if it succeeds, the ACL is looser than
we think, and that is a finding worth reporting.

**(a) The key is readable by exact path.** No contents are printed; this only
asks the kernel whether the open would succeed, then counts bytes.

```bash
KEY=/sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat
test -r "$KEY" && echo "OK: key is readable" || echo "FAIL: key is NOT readable"
wc -c < "$KEY"
ls -l "$KEY"
```

Expected output:

```
OK: key is readable
26
-rw-r-----+ 1 cwang31 ps-users 26 Apr 14 11:12 /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat
```

The `26` is the byte count of the key file as of 2026-04-14; if the key is ever
rotated this number can change, and that is fine — what matters is that `wc`
succeeded rather than printing a permission error. The trailing `+` on the mode
string means the file carries a POSIX ACL. Group is `ps-users`, group bits are
`r--`: that is your read access, and it is why you never need `ps-data`.

**(b) Listing the containing directory must FAIL.**

```bash
ls /sdf/group/lcls/ds/dm/apps/dev/env
```

Expected output — an error, on stderr, with a non-zero exit status:

```
ls: cannot open directory '/sdf/group/lcls/ds/dm/apps/dev/env': Permission denied
```

**This is a prediction, not a measurement.** Run as `cwang31` — who is in
`ps-data` — that same `ls` succeeds with exit status `0` and lists six `.dat`
files. Yours is the first run that can actually produce the denial, which is
exactly why it is worth doing.

That is the correct, intended result. It is not a broken setup and it is not
something to work around. `getfacl` on the directory explains it; run this too,
it is short and it is the single most useful thing you can send back:

```bash
getfacl -p /sdf/group/lcls/ds/dm/apps/dev/env
ls -ld /sdf/group/lcls/ds/dm/apps/dev/env
```

Expected (this is the exact output captured as `cwang31`; yours should be
identical, since `getfacl` reports the ACL rather than your access to it):

```
# file: /sdf/group/lcls/ds/dm/apps/dev/env
# owner: cwang31
# group: ps-data
# flags: -s-
user::rwx
user:cwang31:rwx
group::r-x
group:ps-users:--x
mask::rwx
other::---
default:user::rwx
default:user:cwang31:rwx
default:group::r-x
default:mask::rwx
default:other::r-x

drwxrws---+ 1 cwang31 ps-data 0 May  6 17:24 /sdf/group/lcls/ds/dm/apps/dev/env
```

`group:ps-users:--x` is only half the trick: search permission on the
directory, no read permission, so you can walk *through* `env/` but never
enumerate it. The other half is on the key file itself, which is group-owned by
`ps-users` — that is where your read comes from. Neither half works alone.

If `getfacl` on the directory itself is denied for you, say so — that is another
genuine finding. Every parent directory on the path is world-traversable, which
is what makes the exact-path read reach the file at all:

```
drwxr-xr-x  7 root      root     /sdf
drwxrwxr-x  1 root      root     /sdf/group
drwxrwsr-x  1 wilko     ps-pcds  /sdf/group/lcls
drwxr-sr-x  1 wilko     ps-pcds  /sdf/group/lcls/ds
drwxr-sr-x  1 psdatmgr  xs       /sdf/group/lcls/ds/dm
drwxr-sr-x  1 psdatmgr  xs       /sdf/group/lcls/ds/dm/apps
drwxrwsr-x+ 1 psdatmgr  ps-data  /sdf/group/lcls/ds/dm/apps/dev
```

### 2.3 Confirm the shared skills tree is readable, and count it

```bash
ls -ld /sdf/group/lcls/ds/dm/apps/dev/claude
ls -ld /sdf/group/lcls/ds/dm/apps/dev/claude/skills
ls -1 /sdf/group/lcls/ds/dm/apps/dev/claude/skills | wc -l
```

Expected output:

```
drwxr-s---+ 1 cwang31 ps-users 0 Aug 26 22:39 /sdf/group/lcls/ds/dm/apps/dev/claude
drwxr-s---+ 1 cwang31 ps-users 0 Aug 27 00:15 /sdf/group/lcls/ds/dm/apps/dev/claude/skills
17
```

Note that unlike `env/`, this directory **is** readable to you — group is
`ps-users` with `r-x`, and `other` is `---`. Listing it should work.

The 17 skills, in `ls` order:

```
ask-ami
askcode
ask-epics
ask-lcls2
ask-nersc
ask-olcf
ask-s3df
ask-slac-ai-tools
ask-slurm-s3df
ask-smalldata
ask-tiled
confluence-search
cuda-docs
docs-search
elog-search
experimental-hutch-python
xpm-seq
```

Also prove you can read *inside* a skill, not just list the directory — the
symlinks the installer creates are worthless if the files behind them are not
readable:

```bash
ls -l /sdf/group/lcls/ds/dm/apps/dev/claude/skills/askcode
head -1 /sdf/group/lcls/ds/dm/apps/dev/claude/skills/askcode/SKILL.md
```

Expected: two files, then the first line of `SKILL.md`, which is the opening
delimiter of its YAML front matter:

```
-rw-r--r--+ 1 cwang31 ps-users  699 Aug 26 20:41 env.sh
-rw-r--r--+ 1 cwang31 ps-users 6131 Aug 26 22:40 SKILL.md
---
```

Both files do carry `other::r--`, but that is not how you reach them — every
directory above them is `drwxr-s---`, so `ps-users` membership is still what
gets you in.

### 2.4 Confirm you can run the shared binary

**You do not need to install Claude Code.** Since 2026-08-28 the binary is
deployed for `ps-users` and `claude-lcls` runs that one and only that one. A
personal install is never read — not as a fallback, not at all.

```bash
ls -l /sdf/group/lcls/ds/dm/apps/dev/claude/bin/current
/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current --version
```

Expected shape:

```
lrwxrwxrwx 1 cwang31 ps-users 16 Aug 28 10:33 .../bin/current -> versions/2.1.235
2.1.235 (Claude Code)
```

If the first command says permission denied or no such file, you are probably
not in `ps-users` — re-check §2.1. That is the same root cause as an unreadable
key file, and it has the same remedy: ask for `ps-users` membership. **Do not
work around it by installing Claude Code into your home directory**; the
installer does not use a personal install, so it would change nothing.

> **This is the check the publisher cannot run.** cwang31 is in `ps-data` as well
> as `ps-users`, so a successful run there does not prove a `ps-users`-only
> member can reach the tree. The ACLs say you can. You running the two commands
> above is what turns that from inference into fact — please report the result
> either way.

If you already have your own `claude`, it stays exactly as it is. It keeps using
your own install and your own `~/.claude/`. Nothing here touches it.

---

## 3. How to obtain the installer

Three candidate routes were checked on the host. **Route A is the one to use.**
It was the broken one when this document was first written; publishing the
installer to the shared tree on 2026-08-28 fixed it.

### Route A — the shared read-only tree: **THIS IS NOW THE EASY ONE**

> **Changed 2026-08-28.** This section used to read "DOES NOT WORK", because at
> the time it was written the installer had not been published to the shared
> tree and that campaign was forbidden from writing there. Both facts have since
> changed. Route A is now the recommended route and needs no clone.

The installer and the binary are both published under
`/sdf/group/lcls/ds/dm/apps/dev/claude/`, readable by `ps-users`:

```
$ ls -l /sdf/group/lcls/ds/dm/apps/dev/claude/
drwxr-sr-x+ 1 cwang31 ps-users     0 Aug 28 10:33 bin
-rwxr-xr-x+ 1 cwang31 ps-users 32519 Aug 28 10:39 install-claude-lcls.sh
drwxr-s---+ 1 cwang31 ps-users     0 Aug 27 00:15 skills
```

Run it straight from there — it is mode `0755`, so you can read and execute it
without copying anything:

```bash
/sdf/group/lcls/ds/dm/apps/dev/claude/install-claude-lcls.sh --dry-run
/sdf/group/lcls/ds/dm/apps/dev/claude/install-claude-lcls.sh
```

`bin/` beside it holds the shared Claude Code binary (see §2.4). The published
installer is kept byte-identical to the repo copy by
`tools/claude-binary/scripts/publish-claude-binary.sh installer`, so this is not
a stale hand-copy that drifts.

Routes B and C below are kept for the record and as fallbacks.

### Route B — cwang31's repo directory on disk: DOES NOT WORK for you

The repo lives at
`/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode`. Walking that
path:

```
drwxr-s---+ 1 psdatmgr ps-data  /sdf/data/lcls/ds/prj/prjdat21
drwxrws---+ 1 psdatmgr ps-data  /sdf/data/lcls/ds/prj/prjdat21/results
drwxrws---+ 1 cwang31  ps-data  /sdf/data/lcls/ds/prj/prjdat21/results/cwang31
drwxrws---+ 1 cwang31  ps-data  .../deploy-opencode
```

`getfacl` on `prjdat21` gives named-group entries for `ps-data`, `ps-prj` and
`prjdat21` only, and `other::---`:

```
group::r-x
group:ps-data:r-x
group:ps-prj:r-x
group:prjdat21:r-x
mask::r-x
other::---
```

There is no `ps-users` entry anywhere on that path. A `ps-users` member who is
not also in `ps-data`, `ps-prj` or `prjdat21` cannot even traverse into
`prjdat21`, so the repo directory is unreachable. And the installer file itself
is `-rwxrwx--x+` with `other::--x` — execute-only, not readable — so even
traversal would not let you copy it.

If you *are* in one of `ps-data` / `ps-prj` / `prjdat21`, this route works and
you can just run the script in place. Check with `id -nG`. Most `ps-users`
members are not.

### Route C — clone from GitHub: works, but no longer necessary

The repo is **public**: `https://github.com/carbonscott/deploy-opencode`. An
anonymous HTTPS clone was tested from `sdfiana025` and succeeded:

```bash
git clone --depth 1 https://github.com/carbonscott/deploy-opencode.git /tmp/claude-lcls-clone
ls -l /tmp/claude-lcls-clone/claude/install-claude-lcls.sh
```

Observed:

```
clone rc=0
-rwxr-xr-x 1 <you> <grp> 39286 <date> /tmp/claude-lcls-clone/claude/install-claude-lcls.sh
876
8af7323f02dc36b7be91490e3a7375ba  /tmp/claude-lcls-clone/claude/install-claude-lcls.sh
```

That the repo is genuinely public was re-checked two ways: `curl -s -o /dev/null
-w '%{http_code}' https://api.github.com/repos/carbonscott/deploy-opencode`
returns `200` and the JSON says `"private": false`; and `GIT_TERMINAL_PROMPT=0
git -c credential.helper= ls-remote https://github.com/carbonscott/deploy-opencode.git`
lists every ref without prompting for a credential.

The fixes for the unwritable-rc, symlinked-rc and blank-line-accumulation cases
described in section 8, plus a second round of corrections to the rc-refusal
paths, are on `main` as of merge commit
`b80ed6d8283668570a0aaa7cd50e82dbb1c59480` (PR #20). A plain clone of the
default branch gives you the right file. The branch `claude-lcls-wiring` the
work was developed on has been deleted, so do not ask for it by name.

Verify what you have before running it:

```bash
wc -l install-claude-lcls.sh   # expect 876
md5sum install-claude-lcls.sh  # expect 8af7323f02dc36b7be91490e3a7375ba
bash -n install-claude-lcls.sh # expect complete silence
```

If you get 496 / `6cb70eec...`, 603 / `a8ca2089...`, 792 / `923f10da...` or
856 / `c2d2bb13...` instead, you have an older installer. Re-clone from `main`.

---

## 4. Install

```bash
bash /path/to/install-claude-lcls.sh
```

Run it with `bash`, not `sh` — the script uses `< <(...)` process substitution,
which `sh` cannot parse. It is safe to re-run; a second run refreshes the block
rather than duplicating it. If you want to see what it would do first:

```bash
bash /path/to/install-claude-lcls.sh --dry-run
```

### Expected output

The following is **real captured output**, not a mock-up. It was produced on
2026-08-28 on `sdfiana025` by `cwang31`, running the installer on `main`
against a **scratch `HOME` of
`/tmp/ldr-gt/s2/home`** with `PATH=/usr/bin:/bin` — no personal Claude Code and
no personal `uv` reachable at all, so every path named below is a shared one and
the `Verification` step is a genuine live completion through the gateway, not a
stub. Your paths will show your own `$HOME` instead of `/tmp/ldr-gt/s2/home`.
Everything else should match line for line.

Provenance, stated exactly: the capture below was taken from the 792-line
installer (md5 `923f10da37c971cb5fe57f61dcbcbc98`) and then re-run against the
current 876-line one (md5 `8af7323f02dc36b7be91490e3a7375ba`) on 2026-08-28. The
two runs agreed line for line, differing only in the scratch `HOME` path. That
is expected: the change between them alters what the installer *writes* into
`settings.json`, never what it *prints*.

```


── Preflight
  ✓ claude found: /sdf/group/lcls/ds/dm/apps/dev/claude/bin/current (2.1.235 (Claude Code))
  ✓ shared team binary, resolving to versions/2.1.235
  ✓ shared tools on PATH: /sdf/group/lcls/ds/dm/apps/dev/bin (uv 0.9.8)
  ✓ key readable: /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat
  ✓ gateway reachable: https://ai-api.slac.stanford.edu (HTTP 200)

── Config dir: /tmp/ldr-gt/s2/home/.claude-lcls
  ✓ wrote /tmp/ldr-gt/s2/home/.claude-lcls/settings.json (mode 600)
  ✓ no key is stored — apiKeyHelper reads it from /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat at runtime

── Shared skills: /sdf/group/lcls/ds/dm/apps/dev/claude/skills
  ✓ linked 17 shared skill(s) into /tmp/ldr-gt/s2/home/.claude-lcls/skills

── Shell function: claude-lcls()
  ✓ appended to /tmp/ldr-gt/s2/home/.bashrc

── Verification
  ✓ live completion succeeded through https://ai-api.slac.stanford.edu

Done. Start a new shell (or: source ~/.bashrc), then:

    claude-lcls                       # interactive, SLAC gateway
    claude-lcls -p 'hello'            # one-shot
    claude                           # your own setup, unchanged```

Exit status `0`.

That is **ten** `✓` lines. Things that will legitimately differ for you:

* `✓ appended to ...` becomes `✓ refreshed in ...` on any re-run.
* If you have both a `~/.bashrc` and a `~/.zshrc`, you get one `appended`/
  `refreshed` line per file. If you have neither, the script creates `~/.bashrc`.
* If you already have a `~/.claude/settings.json`, Preflight prints one extra
  line — `✓ your existing ~/.claude/settings.json will NOT be modified` — for
  eleven `✓` lines instead of ten. The scratch `HOME` used above had none.

Preflight also prints a second binary line —
`✓ shared team binary, resolving to versions/<ver>` — naming the version
`bin/current` points at. Whether you have a personal `claude` makes no
difference to any of this; the script does not look for one.

The only case that adds `WARN:` lines is a deliberate `CLAUDE_LCLS_BIN`
override, which announces itself twice before the first `✓`. If you did not set
that variable, you should see no warnings at all.

---

## 5. Post-install checks

### 5.1 The settings file and its mode

```bash
stat -c '%a %n' ~/.claude-lcls ~/.claude-lcls/settings.json
```

Expected:

```
700 /home/<you>/.claude-lcls
600 /home/<you>/.claude-lcls/settings.json
```

`600` is not cosmetic — it is the check that the config a gateway credential
flows through is not readable by anyone else. Anything wider is a bug; report it.

The file contains **no key**. It contains an `apiKeyHelper` that reads the key
from its path at runtime. Confirm that:

```bash
cat ~/.claude-lcls/settings.json
```

Expected — 1112 bytes, md5 `ac5941576b46489d51d7ee7caacb443b`. The two values
that can change it are `KEY_FILE` and `BASE_URL`; both are at their defaults
here. `LCLS_DIR` does not appear in the file at all, only in the path it is
written to.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",

  "apiKeyHelper": "cat /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat",

  "env": {
    "ANTHROPIC_BASE_URL": "https://ai-api.slac.stanford.edu",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "us.anthropic.claude-opus-5[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "us.anthropic.claude-sonnet-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "ANTHROPIC_CUSTOM_MODEL_OPTION": "us.anthropic.claude-sonnet-4-6",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_NAME": "Sonnet 4.6",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION": "Previous Sonnet, kept selectable via the SLAC gateway",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_AUTOUPDATER": "1"
  },

  "skipWebFetchPreflight": true,

  "attribution": {
    "commit": "Generated with AI\n\nCo-Authored-By: SLAC AI",
    "pr": ""
  },

  "permissions": {
    "defaultMode": "auto"
  },

  "tui": "fullscreen",
  "verbose": false,
  "showThinkingSummaries": false,
  "autoMemoryEnabled": false
}
```

#### Which models you get

The three `ANTHROPIC_DEFAULT_*_MODEL` entries map Claude Code's `opus`, `sonnet`
and `haiku` aliases onto the Bedrock ids the SLAC gateway serves. So `/model
opus` gives you **Opus 5** and `/model sonnet` gives you **Sonnet 5** — those are
the defaults, and neither is Claude Code's own default choice, they are this
deployment's.

The gateway serves more than three Anthropic models. Measured on 2026-08-28, it
lists Opus 5, Opus 4.8, Opus 4.7, Opus 4.6, Sonnet 5, Sonnet 4.6 and Haiku 4.5,
alongside a number of non-Anthropic models. An alias can only point at one id,
so the rest are reachable in two ways:

* **`ANTHROPIC_CUSTOM_MODEL_OPTION`** adds one extra entry to the `/model`
  picker. Claude Code appends it to the list rather than replacing anything,
  labelled by `_NAME` and subtitled by `_DESCRIPTION`. There is exactly one such
  slot — no numbered second one — and it is spent on **Sonnet 4.6**.
* **`--model` with a full id** reaches anything the gateway serves without using
  the slot, e.g. `claude-lcls --model us.anthropic.claude-opus-4-8`.

Four ids were checked against the live gateway on 2026-08-28 and each returned a
completion at exit 0: `us.anthropic.claude-opus-5[1m]`,
`us.anthropic.claude-sonnet-5`, `us.anthropic.claude-sonnet-4-6` and
`us.anthropic.claude-opus-4-8`.

#### What the last six keys do, and why they are here

`apiKeyHelper` and `env.ANTHROPIC_BASE_URL` are required — without them
`claude-lcls` does not reach the gateway. Everything from `permissions` down is
a **team default**: a preference, not a requirement, set so that everyone starts
from the same behaviour instead of from whatever each Claude Code release
happens to default to.

| Key | Effect |
| --- | --- |
| `permissions.defaultMode: "auto"` | Claude classifies each action and prompts only for the ones that need a human. Only a **user-level** settings file may grant this; a repo-level one cannot. This file is the user-level one, because `CLAUDE_CONFIG_DIR` points at its directory. |
| `tui: "fullscreen"` | The fullscreen renderer — what you would otherwise get by running `/tui fullscreen` every session. |
| `verbose: false` | Truncated tool output rather than full. |
| `showThinkingSummaries: false` | No API-side thinking summaries. |
| `autoMemoryEnabled: false` | Claude neither reads nor writes the auto-memory directory. |
| `env.DISABLE_AUTOUPDATER: "1"` | No self-update. Redundant today — `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` above already disables the updater — but it names the intent directly, so dropping the traffic flag later cannot silently re-enable updates of a binary you have no write access to. |

`verbose` and `showThinkingSummaries` pin what 2.1.235 already defaults to. The
other four change behaviour — auto-memory in particular is **on** unless the
setting says otherwise.

Two spellings are worth knowing, because both are easy to get wrong and neither
failure is visible:

* There is **no** `memory` object and **no** `autoMemory` key in the settings
  schema. The real key is top-level `autoMemoryEnabled`. Checked against both
  2.1.235 and 2.1.251.
* There is **no** settings key for the auto-updater at all. `env.DISABLE_AUTOUPDATER`
  is the supported control, and is literally what Claude Code's own settings
  migration writes when a user turns auto-updates off. In 2.1.235 the updater
  reports itself disabled for any of `DISABLE_UPDATES`, `DISABLE_AUTOUPDATER` or
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` — three names for one switch.

Both matter because **Claude Code ignores unknown settings keys in silence** —
no warning, no error, no effect. Measured: a settings file carrying a
deliberately invented key ran a one-shot to completion with exit `0` and empty
stderr. A near-miss spelling therefore looks exactly like a working one. If you
edit this file, verify the behaviour changed rather than assuming the key took.

### 5.2 The skill symlinks

```bash
ls -1 ~/.claude-lcls/skills | wc -l
find ~/.claude-lcls/skills -maxdepth 1 -type l | wc -l
ls -l ~/.claude-lcls/skills | head -4
```

Expected — 17 entries, all 17 of them symlinks, each pointing into the shared
tree:

```
17
17
total 0
lrwxrwxrwx 1 <you> <grp> 52 Aug 27 13:54 ask-ami -> /sdf/group/lcls/ds/dm/apps/dev/claude/skills/ask-ami
lrwxrwxrwx 1 <you> <grp> 52 Aug 27 13:54 askcode -> /sdf/group/lcls/ds/dm/apps/dev/claude/skills/askcode
lrwxrwxrwx 1 <you> <grp> 54 Aug 27 13:54 ask-epics -> /sdf/group/lcls/ds/dm/apps/dev/claude/skills/ask-epics
```

A count below 17, or any link that fails `test -e`, is the group-permissions
question failing. Check the dangling ones explicitly:

```bash
for l in ~/.claude-lcls/skills/*; do [ -e "$l" ] || echo "DANGLING: $l"; done
```

Expected: no output.

### 5.3 The marker block in your rc file

```bash
grep -n 'claude-lcls' ~/.bashrc
```

Expected — exactly one `>>>` line and one `<<<` line, wrapping the function:

```
2:# >>> claude-lcls >>>
3:# Claude Code against the SLAC AI Gateway. Installed by install-claude-lcls.sh.
9:claude-lcls() {
10:    local _bin="${CLAUDE_LCLS_BIN:-/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current}"
12:        echo "claude-lcls: shared Claude Code binary is not runnable: $_bin" >&2
16:    CLAUDE_CONFIG_DIR="/home/<you>/.claude-lcls" "$_bin" "$@"
18:# <<< claude-lcls <<<
```

Line numbers depend on how long your existing rc file is; what matters is that
`grep -c 'claude-lcls >>>' ~/.bashrc` prints `1`, never `2`. The full block, as
written:

```bash
# >>> claude-lcls >>>
# Claude Code against the SLAC AI Gateway. Installed by install-claude-lcls.sh.
# Your plain `claude` is untouched and keeps using ~/.claude/.
#
# Runs the shared team binary, resolved at CALL time rather than baked to a
# version, so a bump or a rollback on the deploy side reaches you with nothing
# to re-run here. CLAUDE_LCLS_BIN overrides it if you deliberately set one; a
# personal install never does.
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
    PATH="$_path" CLAUDE_CONFIG_DIR="/home/<you>/.claude-lcls" "$_bin" "$@"
}
# <<< claude-lcls <<<
```

The `PATH` line appends the shared team tools directory, which is where `uv`
lives. Several skills call a bare `uv run`, and nothing on S3DF puts `uv` on
`PATH` by default. Appended rather than prepended, so your own `uv` still wins
if you have one.

> **Changed 2026-08-28.** This block used to resolve a binary through
> `command -v claude` and then `$HOME/.local/share/claude/versions/*`. It no
> longer does. If your rc still carries the old three-branch form, re-run the
> installer — it refreshes the block in place.

Your own `~/.claude/` and `~/.claude.json` are not touched by any of this. The
`claude` command keeps working exactly as before.

### 5.4 First real use

```bash
source ~/.bashrc
type claude-lcls | head -2
claude-lcls -p 'Reply with exactly: PONG' --model sonnet
```

Expected — captured from the scratch-HOME rehearsal:

```
claude-lcls is a function
claude-lcls () 
PONG
```

Exit status `0`. `PONG` on stdout means the whole chain works end to end: the
shell function resolved a binary, `CLAUDE_CONFIG_DIR` pointed Claude Code at
`~/.claude-lcls`, `apiKeyHelper` read the key straight out of the ACL-protected
directory *as you*, and the gateway accepted it.

That last clause is the actual experiment. If `PONG` comes back for a user who
is not in `ps-data`, the ACL design is proven.

---

## 6. What to send back to cwang31

Paste the output of exactly these, in one message. They are chosen so the ACL
question and the group-permissions question are both answerable from the text
alone, without another round trip.

```bash
# --- identity and host
hostname
id -nG

# --- key ACL: readable by path, not listable as a directory
KEY=/sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat
test -r "$KEY" && echo "key readable: YES" || echo "key readable: NO"
wc -c < "$KEY"
ls -l "$KEY"
ls /sdf/group/lcls/ds/dm/apps/dev/env ; echo "ls-dir exit=$?"
getfacl -p /sdf/group/lcls/ds/dm/apps/dev/env

# --- shared skills tree
ls -ld /sdf/group/lcls/ds/dm/apps/dev/claude/skills
ls -1 /sdf/group/lcls/ds/dm/apps/dev/claude/skills | wc -l
head -1 /sdf/group/lcls/ds/dm/apps/dev/claude/skills/askcode/SKILL.md

# --- shared binary: THE check the publisher cannot run for you
BIN=/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current
ls -ld /sdf/group/lcls/ds/dm/apps/dev/claude/bin
ls -l "$BIN"; readlink "$BIN"
test -x "$BIN" && echo "binary executable: YES" || echo "binary executable: NO"
"$BIN" --version
getfacl -p /sdf/group/lcls/ds/dm/apps/dev/claude/bin

# --- which installer you ran
wc -l /path/to/install-claude-lcls.sh
md5sum /path/to/install-claude-lcls.sh

# --- post-install state
stat -c '%a %n' ~/.claude-lcls ~/.claude-lcls/settings.json
ls -1 ~/.claude-lcls/skills | wc -l
find ~/.claude-lcls/skills -maxdepth 1 -type l | wc -l
for l in ~/.claude-lcls/skills/*; do [ -e "$l" ] || echo "DANGLING: $l"; done
grep -c 'claude-lcls >>>' ~/.bashrc

# --- isolation: your own config was not created or touched
ls -ld ~/.claude 2>/dev/null || echo "no personal ~/.claude — expected if you never installed Claude Code"
ls -l ~/.claude.json 2>/dev/null || echo "no personal ~/.claude.json — expected"
du -sh ~/.claude-lcls

# --- proof of life
claude-lcls -p 'Reply with exactly: PONG' --model sonnet
```

Plus **the complete installer output**, from the blank line before `── Preflight`
to the last line, including any `WARN:` lines. Scroll-back is fine; better is to
have run it as `bash install-claude-lcls.sh 2>&1 | tee /tmp/claude-lcls-install.log`.

Do **not** send: the contents of `slac-key.dat`, or anything from
`~/.claude/`. `wc -c` and `ls -l` on the key are enough.

The three lines that carry the most information, if you send nothing else:
`id -nG`, the `ls`-of-directory failure, and `wc -c < "$KEY"` succeeding
anyway.

---

## 7. Rollback

```bash
bash /path/to/install-claude-lcls.sh --uninstall
```

Expected output — captured from a scratch-HOME run, immediately after a
successful install:

```

── Removing claude-lcls
  ✓ stripped from /tmp/ldr-h3-home/.bashrc (backup: /tmp/ldr-h3-home/.bashrc.claude-lcls-bak)

── Shared skill links
  ✓ removed 17 skill symlink(s) from /tmp/ldr-h3-home/.claude-lcls/skills

Config dir left in place: /tmp/ldr-h3-home/.claude-lcls
Remove it yourself if you want it gone:  rm -rf /tmp/ldr-h3-home/.claude-lcls
Your own ~/.claude/ was never touched.
```

Exit status `0`. Verified afterwards on the scratch home:

* `~/.bashrc` was returned to its original two lines — byte-identical to the
  pre-install file, same md5 — with no leftover blank line where the block had
  been.
* A backup was written next to it as `~/.bashrc.claude-lcls-bak`.
* `~/.claude-lcls/skills` was removed entirely (17 links deleted, then the empty
  directory `rmdir`-ed).
* The shared tree `/sdf/group/lcls/ds/dm/apps/dev/claude/skills` still held all
  17 skills — the uninstall removes links, and never follows one into the shared
  tree.

`--uninstall` does not always exit `0`. If any rc file was skipped or left
unwritable, it now exits **1** — after printing the `Config dir left in place: …`
block — because an uninstall that left a block behind did not uninstall. In that
case you also get, before the `Config dir` block:

```
  WARN: not writable, left untouched: <rc>
  WARN: the claude-lcls block is STILL PRESENT in the file(s) above.
  WARN: fix the permissions and re-run:  /path/to/install-claude-lcls.sh --uninstall
```

Note that the 17 skill symlinks are removed anyway, so an aborted uninstall
leaves a half-removed state: the shell function is still defined in your rc, the
team skills are gone. Fix the permissions and re-run to finish the job.

The config directory `~/.claude-lcls` is deliberately left behind. It holds
`settings.json`, and — once you have actually run `claude-lcls` even once — the
`backups/`, `projects/` and `sessions/` directories Claude Code writes there for
itself. Delete it yourself with `rm -rf ~/.claude-lcls` if you want a clean
slate. Then `unset -f claude-lcls` in your current shell, or just open a
new one.

---

## 8. Known-good vs known-bad

Every row below was produced by actually running the installer on `sdfiana025`
against a scratch `HOME` under `/tmp`, and the "what the script says" column is
copied from that run. The rc-file rows came from the 693-line installer (md5
`51440d603fd6353fc5d0212b05e653a6`); the three binary rows at the bottom came
from the 792-line shared-binary installer (md5
`923f10da37c971cb5fe57f61dcbcbc98`) on 2026-08-28. Neither was produced by the
current 876-line installer (md5 `8af7323f02dc36b7be91490e3a7375ba`), and both
still hold: the only change since is the team-defaults block written into
`settings.json`, which touches neither the rc-handling code nor the binary
resolution these rows exercise. Two rows could not be produced honestly, because `cwang31` **is** in
`ps-users` and **is** on the SLAC network: the "Not in `ps-users`" row was
forced with `KEY_FILE=/tmp/no-such-key.dat` and the "Off the SLAC network" row
with `BASE_URL=https://127.0.0.1:9`. Both reach the identical code path, so the
message text and the exit status are real; only the cause was simulated.

| Situation | Exit | What the script says |
|---|---|---|
| **Everything fine** | `0` | Eight `✓` lines ending in `✓ live completion succeeded through https://ai-api.slac.stanford.edu`, then the `Done.` block. Nine if you already have a `~/.claude/settings.json`. |
| **Not in `ps-users`** (key unreadable) | `1` | `✗ cannot read /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat`, then `This key is group-readable by 'ps-users'. You are in:` followed by your own `id -nG`, then `Ask for 'ps-users' membership. Do NOT ask anyone to copy the key to you — it is meant to be read in place.` Nothing is written. |
| **Off the SLAC network / VPN** | `1` | `✗ cannot reach https://ai-api.slac.stanford.edu — are you on the SLAC network or VPN?` Preflight dies before any file is created. (A rotated or revoked key gives `✗ gateway rejected the key (HTTP 401). Key may be rotated or revoked.` instead.) |
| **Unwritable rc file** (e.g. mode 444 `~/.bashrc`) | `1` (`0` if another rc succeeded) | Preflight, config dir and all 17 skill links succeed first, then, in this order: `WARN: <rc> is not writable (mode 444, owner <you>).` / `WARN: fix it with: chmod u+w <rc>   (then re-run this script)` / `WARN: left <rc> COMPLETELY untouched -- nothing stripped, nothing appended, no backup written.` / `WARN: not writable, left untouched: <rc>` / `WARN: claude-lcls was NOT installed into the file(s) above; fix the permissions and re-run.` / `✗ claude-lcls could not be installed into ANY shell rc. Fix the file(s) above and re-run.` The rc file is left byte-identical (verified by md5, mode still `444`), and no `.claude-lcls-bak` is written. There is no `── Verification` section at all — the run dies before it. Re-run after `chmod u+w` and it completes — confirmed, exit `0` with exactly one marker pair. If you have two rc files and only one of them is unwritable, the writable one **is** installed: the same five `WARN:` lines appear for the bad file, then `WARN: claude-lcls WAS installed into at least one other rc; continuing.`, and the run proceeds to `── Verification` and exits `0`. The diagnosis is target-aware. For a symlinked rc it first prints `WARN: <rc> is a symlink to <target>; everything below refers to the target.` and everything after that names `<target>`, not `<rc>`. For a writable file sitting in a read-only **directory** it prints `WARN: <target> is writable, but its directory <dir> is not (mode 555, owner <you>).` / `WARN: refreshing an existing block renames a temp file into that directory, so it needs write permission on the DIRECTORY, not on the file.` / `WARN: fix it with: chmod u+w <dir>   (then re-run this script)` — the remedy names the directory, not the file. Under `DRY_RUN=1` the same five `WARN:` lines appear, then `WARN: a real run would stop here with exit 1: no usable shell rc.`, and the script continues into `── Verification`, prints `Dry run complete. Nothing was written.` and exits `0`. |
| **Symlinked rc file** (dotfiles / stow / chezmoi) | `0` | Nothing special — `✓ appended to ~/.bashrc` on the first run and `✓ refreshed in ~/.bashrc` on the second. The point is what does *not* happen: `~/.bashrc` stays a symlink, the block lands in the physical file behind it, and a second run leaves exactly one marker pair rather than replacing the link with a regular file. A link that cannot be resolved is refused instead of followed: `WARN: <rc> is a symlink that cannot be resolved: a missing directory somewhere in the chain, or a symlink loop.` / `WARN: inspect it with:  ls -l <rc>   and   readlink -f <rc>`, and the file then takes the unwritable-rc verdict above — exit `1` unless another rc took the block. A broken chain and a symlink loop produce the identical pair of lines; the installer cannot and does not distinguish them. |
| **Broken markers** (a `# >>> claude-lcls >>>` with no matching `# <<< claude-lcls <<<`) | `1` (`0` if another rc succeeded) | `WARN: <rc> has an UNTERMINATED claude-lcls block: a '# >>> claude-lcls >>>' line with no matching '# <<< claude-lcls <<<' (or a second '# >>> claude-lcls >>>' inside an open block).` / `WARN: left <rc> COMPLETELY untouched — nothing stripped, nothing appended, no backup written.` / `WARN: fix it by hand (delete the stray '# >>> claude-lcls >>>' line, or add the missing '# <<< claude-lcls <<<') so exactly one begin/end pair remains, then re-run.` / `WARN: left untouched and still needing manual repair: <rc>` / `WARN: claude-lcls was NOT installed into the file(s) above; repair the markers and re-run.` / `✗ claude-lcls could not be installed into ANY shell rc. Fix the file(s) above and re-run.` The rc is left byte-identical (md5 verified) and no `.claude-lcls-bak` is written. Broken markers share one verdict with the unwritable case: if no rc took the block the run exits `1`; if a different rc did take it, you get `WARN: claude-lcls WAS installed into at least one other rc; continuing.` and exit `0`. Read the warnings; a `0` there does not mean the function was installed in *this* file. |
| **No personal `claude` anywhere** — nothing on `PATH`, no `~/.local/share/claude` | `0` | **A normal, successful install.** Verified 2026-08-28 against a scratch `HOME` with `PATH=/usr/bin:/bin`: preflight resolved `/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current (2.1.235 (Claude Code))`, 17 skills linked, live `PONG` through the gateway. This row used to read exit `1` / "Install Claude Code first"; that is no longer the behaviour. |
| **Shared binary unreadable** (not in `ps-users`) | `1` | `✗ cannot run the Claude Code binary: /sdf/.../claude/bin/current`, then your group list and the advice to ask for `ps-users` membership — explicitly *not* to install Claude Code yourself. Nothing is written; not even the config dir. |
| **`CLAUDE_LCLS_BIN` set to a bad path** | `1` | Two `WARN:` lines naming the override and how to unset it, then `✗ cannot run the Claude Code binary: <that path>` and `CLAUDE_LCLS_BIN is set to a path that is not executable.` Verified 2026-08-28. |

### How rows 4 and 5 were exercised

Row 4: a scratch `HOME` whose `.bashrc` was `chmod 444`. The gate that produces
it (`rc_is_writable`) runs **before** the append, and asks for exactly the
permission the operation needs: write on the FILE for an append, and write on
the DIRECTORY as well only when the rc already carries a block, because that is
the refresh path and it renames a temp file into place. Demanding both
unconditionally would refuse an rc that a plain append would have handled
perfectly well. Afterwards the rc was confirmed still mode `444` and
byte-identical to the pre-run file by md5, with no `.claude-lcls-bak` written.
Everything earlier in the run — config dir, `settings.json` at mode `600`, all
17 skill symlinks — is still created before the gate is reached, so a re-run
after `chmod u+w` only has the rc left to do.

Row 5: a scratch `HOME` where `.bashrc` was a symlink to
`dotfiles/bashrc`, installed into twice. After the second run `.bashrc` was
still `lrwxrwxrwx ... -> .../dotfiles/bashrc` and the physical file contained
exactly one begin marker. Without this fix the second run replaces the symlink
with a regular file, orphaning the dotfiles copy with a stale block that
`--uninstall` can never reach — and the next `stow` puts it straight back.

---

## See also

`docs/claude-code-lcls-setup.md` in this repo — the reference guide for what
`claude-lcls` is and how the gateway config is put together.
