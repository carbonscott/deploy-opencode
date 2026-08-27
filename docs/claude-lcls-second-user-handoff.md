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

### 2.4 Confirm you have a `claude` binary

The installer needs a runnable Claude Code binary. It looks for `claude` on
`PATH` first, and falls back to the newest versioned binary under
`$HOME/.local/share/claude/versions`.

```bash
command -v claude || echo "(no claude on PATH)"
ls -d "$HOME"/.local/share/claude/versions/* 2>/dev/null | sort -V | tail -1
```

Either line producing a path is enough. A concrete example — on `sdfiana025`
today `cwang31` has **no** shim on `PATH` and only the versioned binaries:

```
(no claude on PATH)
/sdf/home/c/cwang31/.local/share/claude/versions/2.1.235
```

Confirm whichever one you found actually runs:

```bash
"$(command -v claude || ls -d "$HOME"/.local/share/claude/versions/* | sort -V | tail -1)" --version
```

Expected shape:

```
2.1.235 (Claude Code)
```

If both lines come up empty, install Claude Code first. The installer will stop
with `no 'claude' on PATH and no versioned binary under ...` and write nothing.

---

## 3. How to obtain the installer

Three candidate routes were checked on the host. **Only one works for you
today.**

### Route A — the shared read-only tree: DOES NOT WORK

`/sdf/group/lcls/ds/dm/apps/dev/claude/` is the deployed tree you can read, and
it contains **only** `skills/`:

```
$ ls -l /sdf/group/lcls/ds/dm/apps/dev/claude/
total 0
drwxr-s---+ 1 cwang31 ps-users 0 Aug 27 00:15 skills
```

```
$ find /sdf/group/lcls/ds/dm/apps/dev -name 'install-claude-lcls*'
(no output — the whole deploy root was searched, not just claude/)
```

The installer is not published there. Nothing under
`/sdf/group/lcls/ds/dm/apps/` may be written during this campaign, so it will
not appear there as part of this exercise either.

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

### Route C — clone from GitHub: THIS IS THE ONE THAT WORKS

The repo is **public**: `https://github.com/carbonscott/deploy-opencode`. An
anonymous HTTPS clone was tested from `sdfiana025` and succeeded:

```bash
git clone --depth 1 https://github.com/carbonscott/deploy-opencode.git /tmp/claude-lcls-clone
ls -l /tmp/claude-lcls-clone/claude/install-claude-lcls.sh
```

Observed:

```
clone rc=0
-rwxr-xr-x 1 <you> <grp> 29467 <date> /tmp/claude-lcls-clone/claude/install-claude-lcls.sh
693
51440d603fd6353fc5d0212b05e653a6  /tmp/claude-lcls-clone/claude/install-claude-lcls.sh
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
wc -l install-claude-lcls.sh   # expect 693
md5sum install-claude-lcls.sh  # expect 51440d603fd6353fc5d0212b05e653a6
bash -n install-claude-lcls.sh # expect complete silence
```

If you get 496 / `6cb70eec...` or 603 / `a8ca2089...` instead, you have a
pre-merge installer. Re-clone from `main`.

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
2026-08-27 on `sdfiana025` by `cwang31`, running the 693-line installer on
`main` (md5 `51440d603fd6353fc5d0212b05e653a6`) against a **scratch `HOME` of
`/tmp/ldr-gt/s1b/home`** with the real `2.1.235` Claude Code binary symlinked
onto a scratch `PATH` — so the `Verification` step is a genuine live completion
through the gateway, not a stub. Your paths will show your own `$HOME` and your
own binary instead of `/tmp/ldr-gt/s1b/home` and `/tmp/ldr-gt/s1b/bin/claude`.
Everything else should match line for line.

```

── Preflight
  ✓ claude found: /tmp/ldr-gt/s1b/bin/claude (2.1.235 (Claude Code))
  ✓ key readable: /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat
  ✓ gateway reachable: https://ai-api.slac.stanford.edu (HTTP 200)

── Config dir: /tmp/ldr-gt/s1b/home/.claude-lcls
  ✓ wrote /tmp/ldr-gt/s1b/home/.claude-lcls/settings.json (mode 600)
  ✓ no key is stored — apiKeyHelper reads it from /sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat at runtime

── Shared skills: /sdf/group/lcls/ds/dm/apps/dev/claude/skills
  ✓ linked 17 shared skill(s) into /tmp/ldr-gt/s1b/home/.claude-lcls/skills

── Shell function: claude-lcls()
  ✓ appended to /tmp/ldr-gt/s1b/home/.bashrc

── Verification
  ✓ live completion succeeded through https://ai-api.slac.stanford.edu

Done. Start a new shell (or: source ~/.bashrc), then:

    claude-lcls                       # interactive, SLAC gateway
    claude-lcls -p 'hello'            # one-shot
    claude                           # your own setup, unchanged

```

Exit status `0`.

That is **eight** `✓` lines. Things that will legitimately differ for you:

* `✓ appended to ...` becomes `✓ refreshed in ...` on any re-run.
* If you have both a `~/.bashrc` and a `~/.zshrc`, you get one `appended`/
  `refreshed` line per file. If you have neither, the script creates `~/.bashrc`.
* If you already have a `~/.claude/settings.json`, Preflight prints one extra
  line — `✓ your existing ~/.claude/settings.json will NOT be modified` — for
  nine `✓` lines instead of eight. The scratch `HOME` used above had none.

If `claude` is not on your `PATH` and the script has to fall back to a versioned
binary, you additionally get three `WARN:` lines before the first `✓` saying the
launcher shim is missing and naming the binary it used instead. That is a
warning, not a failure; the install continues.

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

Expected — 688 bytes, md5 `f56a1e105ca59444baa66a1185c30864`. The two values
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
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },

  "skipWebFetchPreflight": true,

  "attribution": {
    "commit": "Generated with AI\n\nCo-Authored-By: SLAC AI",
    "pr": ""
  }
}
```

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
4:# >>> claude-lcls >>>
5:# Claude Code against the SLAC AI Gateway. Installed by install-claude-lcls.sh.
9:claude-lcls() {
16:        echo "claude-lcls: no claude binary on PATH or under $HOME/.local/share/claude/versions" >&2
19:    CLAUDE_CONFIG_DIR="/home/<you>/.claude-lcls" "$_bin" "$@"
21:# <<< claude-lcls <<<
```

Line numbers depend on how long your existing rc file is; what matters is that
`grep -c 'claude-lcls >>>' ~/.bashrc` prints `1`, never `2`. The full block, as
written:

```bash
# >>> claude-lcls >>>
# Claude Code against the SLAC AI Gateway. Installed by install-claude-lcls.sh.
# Your plain `claude` is untouched and keeps using ~/.claude/.
# The shim can vanish, so resolve a binary at call time rather than assuming a
# plain "claude" is on PATH.
claude-lcls() {
    local _bin
    _bin="$(command -v claude 2>/dev/null)" || _bin=""
    if [ -z "$_bin" ]; then
        _bin="$(ls -d "$HOME"/.local/share/claude/versions/* 2>/dev/null | sort -V | tail -1)" || _bin=""
    fi
    if [ -z "$_bin" ] || [ ! -x "$_bin" ]; then
        echo "claude-lcls: no claude binary on PATH or under $HOME/.local/share/claude/versions" >&2
        return 127
    fi
    CLAUDE_CONFIG_DIR="/home/<you>/.claude-lcls" "$_bin" "$@"
}
# <<< claude-lcls <<<
```

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

# --- which installer you ran
wc -l /path/to/install-claude-lcls.sh
md5sum /path/to/install-claude-lcls.sh

# --- post-install state
stat -c '%a %n' ~/.claude-lcls ~/.claude-lcls/settings.json
ls -1 ~/.claude-lcls/skills | wc -l
find ~/.claude-lcls/skills -maxdepth 1 -type l | wc -l
for l in ~/.claude-lcls/skills/*; do [ -e "$l" ] || echo "DANGLING: $l"; done
grep -c 'claude-lcls >>>' ~/.bashrc

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

Every row below was produced by actually running the 693-line `main` installer
(md5 `51440d603fd6353fc5d0212b05e653a6`) on `sdfiana025` against a scratch
`HOME` under `/tmp`, and the "what the script says" column is copied from that
run. Two rows could not be produced honestly, because `cwang31` **is** in
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
| **No `claude` binary at all** | `1` | `✗ no 'claude' on PATH and no versioned binary under <your $HOME>/.local/share/claude/versions. Install Claude Code first, then re-run.` — the path is printed expanded, not as the literal `$HOME`. Nothing is written; not even the config dir. |
| **No `claude` on PATH, versioned binary present** | `0` | Three `WARN:` lines about the missing launcher shim, naming the versioned binary it will use, then a normal successful install. |

### How rows 4 and 5 were exercised

Row 4: a scratch `HOME` whose `.bashrc` was `chmod 444`. The gate that produces
it (`rc_is_writable`) runs **before** the append, and checks write permission on
both the file and its directory — the directory because a refresh renames a
temp file into place. Afterwards the rc was confirmed still mode `444` and
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
