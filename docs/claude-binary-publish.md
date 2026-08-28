# Publishing the shared Claude Code binary

**First published:** 2026-08-28 on `sdfiana025`, pin `2.1.235`.
**Tool:** `tools/claude-binary/scripts/publish-claude-binary.sh`.

---

## Why this exists

`install-claude-lcls.sh` used to require a personal Claude Code install and
refuse to run without one. That cost two things.

Seventeen Claude Code skills were deployed at `dev/claude/skills/` but only
reached people who had already installed the harness themselves. And the
personal install proved fragile: the `~/.local/bin/claude` launcher shim was
observed vanishing from a home directory mid-campaign (campaign claims C17 and
C22), leaving `claude-lcls` correctly installed and unable to start. Two people
running `claude-lcls` could also silently be on two different Claude Code
versions against the same gateway.

One team binary, published once, removes all three.

---

## What is published

```
/sdf/group/lcls/ds/dm/apps/dev/claude/        2750 cwang31:ps-users
├── install-claude-lcls.sh                    0755 ps-users   (published by `installer` mode)
├── skills/                                   2750 ps-users   (published by deploy.sh)
└── bin/                                      2755 ps-users
    ├── versions/
    │   └── 2.1.235                           0755 ps-users
    ├── current -> versions/2.1.235
    └── VERSIONS.json                         0644 ps-users
```

`bin/` sits inside `claude/` rather than beside `uv` in `dev/bin/` on purpose.
`claude/` is mode 2750, so its audience is exactly `ps-users` — the same audience
as `dev/env/slac-key.dat` and the deployed skills. `dev/bin/` is 2775 with
`other r-x`, so publishing there would hand the binary to every S3DF user while
the key it needs stays `ps-users`-only.

`current` is a **relative** symlink (`versions/2.1.235`, not an absolute path),
so a rehearsal against a mock `DEPLOY_ROOT` never points back at production.

---

## Measured facts this rests on

| Question | Result |
|---|---|
| Runs from a read-only directory? | Yes. `chmod 555` on the containing dir, `--version` exit 0, directory byte-identical afterwards |
| Writes into its own directory? | No |
| Per-user state | All under `$HOME`; `CLAUDE_CONFIG_DIR` puts it in `~/.claude-lcls/` |
| Library deps | glibc only — `libc`, `libm`, `libpthread`, `libdl`, `librt` — against RHEL 8.10 / glibc 2.28 |
| Auto-updater | Inert. `installMethod` stays unset when a versioned binary is exec'd directly |
| Name-independence | A copy named `claude-2.1.235` still reports `2.1.235`; the filename is not the version source |
| Size | 330,946,864 bytes for 2.1.235 |
| Download time | 331 MB fetched and SHA-256-verified in 2.9 s from `sdfiana025` |
| Space | `/sdf/group` quota view shows 13 T free against ~330 MB per version |

---

## Publishing a new version

Four steps. The first two write nothing to production.

```bash
cd /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode
P=./tools/claude-binary/scripts/publish-claude-binary.sh

# 1. See exactly what would change. Writes nothing.
$P plan 2.1.240

# 2. Download to /tmp and verify against Anthropic's own SHA-256.
#    Refuses on any mismatch; nothing reaches production from a bad download.
$P fetch 2.1.240

# 3. Publish the binary. Does NOT make it live.
CLAUDE_BINARY_ALLOW_PROD=1 $P publish 2.1.240 --yes-really-publish

# 4. Make it live. This is the only step users notice.
CLAUDE_BINARY_ALLOW_PROD=1 $P activate 2.1.240 --yes-really-publish

$P verify
```

`stable` and `latest` work anywhere a version does; the tool resolves them and
records the **concrete** version, so what got published is never a moving name.

### The two gates

Every writing mode refuses twice, the same shape as `deploy-backup.sh restore`:

| Gate | Says |
|---|---|
| `--yes-really-publish` | "I meant to write" |
| `CLAUDE_BINARY_ALLOW_PROD=1` | "I meant to write to **production**" |

A rehearsal against `DEPLOY_ROOT=/tmp/mock-deploy` needs only the first, so the
second stays off everywhere except the real thing. Both were exercised before
the first production publish; each refused with exit 1 and wrote nothing.

---

## Rolling back

One command. `versions/` keeps every version ever published, so the previous one
is already on disk.

```bash
CLAUDE_BINARY_ALLOW_PROD=1 $P activate 2.1.235 --yes-really-publish
```

The symlink is swapped through a temp name and `mv -fT`, so readers never
observe a missing `current`. `activate` reads the expected checksum from
`VERSIONS.json` before falling back to the network — **rollback does not need
the internet**, because the day you have to roll back is a day other things are
already broken.

Rollback was proven end to end on a mock root before the first production
publish: 2.1.235 → 2.1.236 → back to 2.1.235, each confirmed by
`current --version`.

Users need do nothing. The shell function resolves `bin/current` at call time,
so the next `claude-lcls` invocation picks up the flip.

---

## Version policy

- **Pin deliberately.** The tool defaults to `CLAUDE_BINARY_PIN` in `env.sh`,
  not to `latest`. Running the tool on a different day must not silently change
  what the team runs.
- **One variable at a time.** The first publish used 2.1.235 — the version every
  measurement in this repo was made against — so the only new thing was *where*
  the binary lived. A version bump is its own change with its own verification.
- **Keep the previous version.** Never prune the version you just rolled forward
  from; it is the rollback target.
- **Bumping is a decision, not a chore.** There is no auto-update. Claude Code's
  own updater is inert here by construction, which is the intended behaviour: a
  shared binary that updated itself would change what 3748 people run without
  anyone deciding to.

---

## What is deliberately NOT backed up

`claude/bin/` is outside `deploy-backup.sh`'s at-risk set, and must stay outside.

Adding it would take a routine archive from ~150 KB to over 330 MB per run and
make "take a backup first" something people quietly stop doing. It also buys
nothing: every published version is reproducible from its version number and
SHA-256, both recorded in `VERSIONS.json`, and rolling back is a symlink flip
rather than a tar restore.

`deploy-backup.sh` now reports `claude/` as **PARTIAL** rather than CAPTURED so
this limit is visible in the tool's own output, not only here.

---

## Verification

`$P verify` checks, and exits non-zero on any failure:

- directory modes and group on `bin/` and `bin/versions/`
- every published binary's SHA-256 against its `VERSIONS.json` record
- that each binary is executable, and its mode and group
- that `current` is a symlink, points inside `versions/`, and is not dangling
- that `current --version` reports the version `current` points at
- the POSIX ACLs on `bin/`
- that the published installer matches the repo copy

The check that matters most cannot be run by the publisher: **a `ps-users`
member who is not in `ps-data` running the binary.** The ACLs say they can
(`claude/` gives group `r-x`; `dev/env/` carries a `group:ps-users:--x` traverse
entry), but that is inference until a second person runs:

```bash
ls -l /sdf/group/lcls/ds/dm/apps/dev/claude/bin/current
/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current --version
```

---

## Honest limits

- **Cold-exec cost is unmeasured.** Nobody has timed a first `exec` of a 331 MB
  binary off `/sdf/group` on a busy node. opencode's 158 MB team build sets the
  precedent that it is tolerable, but that is precedent, not measurement.
- **A bad pin reaches everyone at once.** That is the trade for uniformity.
  Rollback is one command, and `versions/` never loses the previous binary.
- **`installMethod` being unset is what keeps the updater inert.** It is
  observed behaviour of 2.1.235, not a documented contract. Re-check it when
  bumping across a major version.
- **Nothing watches for drift here.** `tools/skill-drift` scans
  `opencode/skills/` only; it has never looked at `claude/bin/`. `verify` is a
  manual check, not a cron.

## See also

- `docs/claude-code-lcls-setup.md` — the user-facing guide
- `docs/claude-lcls-second-user-handoff.md` — onboarding a second person
- `docs/deploy-rollback.md` §3 — backup scope, and why `claude/bin/` is outside it
- `docs/deploy-permissions.md` §4 — the mkdir/chgrp/chmod order this tool follows
