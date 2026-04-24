# Permissions Migration: Public Skill Dirs → `ps-users`, `elog-copilot` Stays Restricted

**Date:** 2026-04-23
**Scope:** 11 subdirectories under `/sdf/group/lcls/ds/dm/apps/dev/data/`
**Actor:** cwang31 (no admin help required)
**Related:** [slac-lcls/elog-copilot#11](https://github.com/slac-lcls/elog-copilot/issues/11)

## Intent

Align the group ownership of shared skill/data directories with the access policy that was agreed with `tsgit` today on issue #11:

- **Public skill/data dirs** (everything except `elog-copilot/`) should be readable by the broader LCLS community via the `ps-users` POSIX group, and not by random users on the system. Read access only — no group-write.
- **`elog-copilot/`** must remain restricted because it ingests content from the electronic logbook. Access for the `ps-agent` subset is preserved via an existing named ACL entry (`group:ps-agent:r-x`), not by changing primary group.

Earlier, the agreement was ambiguous. Several stale comments on issue #11 discussed alternative schemes (e.g. primary group `ps-agent` for elog-copilot, hypothetical `ps-agent-pub` / `ps-agent-plus` groups). Today's live decision is the one that was implemented: primary group is `ps-users` for everything else, and `elog-copilot` is left alone with its existing ACL-based ps-agent access.

The deeper reason, restated: when tsgit flagged on 2026-03-23 that the entire path chain under `/sdf/group/lcls` is world-`rx`, ACLs on leaf directories are not enough to hide sensitive contents. Fixing this requires tightening the regular UNIX perms on the leaf, which is what this migration does.

## State before

Every dir under `/sdf/group/lcls/ds/dm/apps/dev/data/` — including `elog-copilot` — had primary group `ps-data` and a redundant named ACL entry `group:ps-agent:r-x`. Modes varied:

| Dir | Mode before | Reason for variance |
|---|---|---|
| `confluence-doc`, `daq-logs`, `smartsheet`, `epics-docs`, `elog-copilot` | `drwxrws---` | Already no-world. |
| `cuda-docs`, `nano-isaac`, `nersc-docs`, `olcf-docs`, `sdf-docs`, `tiled-docs` | `drwxrwsr-x` | World-readable (historical). |
| `lcls-catalog` | `drwxrws--x` | World-traverse only (historical). |

Ownership: all dirs owned by `cwang31`. All descendant files owned by `cwang31` (verified via `find ! -user cwang31` returning empty).

## Commands applied

For `epics-docs` (the validation run, done earlier in the day before switching to the uniform command):

```bash
chgrp -R ps-users /sdf/group/lcls/ds/dm/apps/dev/data/epics-docs
chmod -R g-w      /sdf/group/lcls/ds/dm/apps/dev/data/epics-docs
```

For the remaining 10 dirs (uniform command, "tighten to ps-users only"):

```bash
for d in smartsheet cuda-docs nano-isaac daq-logs sdf-docs olcf-docs \
         tiled-docs nersc-docs confluence-doc lcls-catalog; do
  chgrp -R ps-users   /sdf/group/lcls/ds/dm/apps/dev/data/$d
  chmod -R g-w,o-rwx  /sdf/group/lcls/ds/dm/apps/dev/data/$d
done
```

Processing order was smallest-to-largest by file count: `smartsheet` (1) → `cuda-docs` (3) → `nano-isaac` (10) → `daq-logs` (38) → `sdf-docs` (171) → `olcf-docs` (445) → `tiled-docs` (591) → `nersc-docs` (702) → `confluence-doc` (1100) → `lcls-catalog` (3905).

Note: `epics-docs` used `g-w` only (not `g-w,o-rwx`), because it was already `drwxrws---` with no `other` bits — the two forms produce the same end state in that specific case. For all the other dirs, `o-rwx` was needed to strip pre-existing world access.

**`elog-copilot/`: no commands were run. It retains:**
- primary group `ps-data`
- mode `drwxrws---`
- named ACL entry `group:ps-agent:r-x` (+ `default:` counterpart)

## State after (verified)

```
confluence-doc   cwang31:ps-users drwxr-s---
cuda-docs        cwang31:ps-users drwxr-s---
daq-logs         cwang31:ps-users drwxr-s---
epics-docs       cwang31:ps-users drwxr-s---
lcls-catalog     cwang31:ps-users drwxr-s---
nano-isaac       cwang31:ps-users drwxr-s---
nersc-docs       cwang31:ps-users drwxr-s---
olcf-docs        cwang31:ps-users drwxr-s---
sdf-docs         cwang31:ps-users drwxr-s---
smartsheet       cwang31:ps-users drwxr-s---
tiled-docs       cwang31:ps-users drwxr-s---
elog-copilot     cwang31:ps-data  drwxrws---     # unchanged
```

Zero non-`ps-users` descendants were found under each of the 11 converted trees. Setgid bit on directories preserved throughout so new files created by cwang31 inherit `ps-users`. The lone symlink in the tree (`nano-isaac/scripts/data.json → ../reaction_parameters.json`) is internal and relative; unaffected.

## What was intentionally NOT done

1. **Parent `data/` inheritance not flipped.** `/sdf/group/lcls/ds/dm/apps/dev/data/` itself is still setgid-group=`ps-data` with `default:group:ps-agent:r-x`. That means any **new** sibling dir created here still inherits `ps-data` group and a redundant `ps-agent` ACL, not `ps-users`. Every new skill still needs a manual fix-up after creation. This was a deliberate scope cut for today; revisit when there's appetite for a one-shot parent-directory change.

2. **Existing `group:ps-agent:r-x` ACL entries left in place on the 11 converted dirs.** These are redundant — every current ps-agent member is also in ps-users (verified via `comm -23` returning empty). They're not harmful; cleanup is cosmetic and can be done any time with:

   ```bash
   setfacl -R     -x g:ps-agent /sdf/group/lcls/ds/dm/apps/dev/data/<dir>
   setfacl -R -d  -x g:ps-agent /sdf/group/lcls/ds/dm/apps/dev/data/<dir>
   ```

3. **`elog-copilot` primary group not changed to `ps-agent`.** `cwang31` is not a member of `ps-agent` (groups are `gu, ps-users, ps-data`), so `chgrp ps-agent` would require admin help or the addition of cwang31 to ps-agent. Since ps-agent members already have read access via the existing ACL, this was judged unnecessary. If primary-group change is ever wanted for audit cleanliness, open a ticket with psdatmgr.

## Rollback

Each dir's pre-change state is in the "State before" table. General reversal:

```bash
chgrp -R ps-data /sdf/group/lcls/ds/dm/apps/dev/data/<dir>
chmod -R g+w     /sdf/group/lcls/ds/dm/apps/dev/data/<dir>     # restore group-write
```

Plus the `other`-bit restoration per that table:

- For `cuda-docs`, `nano-isaac`, `nersc-docs`, `olcf-docs`, `sdf-docs`, `tiled-docs`:
  `chmod -R o+rX /sdf/group/lcls/ds/dm/apps/dev/data/<dir>`
- For `lcls-catalog`:
  `chmod -R o+X /sdf/group/lcls/ds/dm/apps/dev/data/<dir>`   (directories only — sets execute, not read)
- For `confluence-doc`, `daq-logs`, `smartsheet`, `epics-docs`: nothing (other was already `---`).

## Who can see what, now

| Group / user | Public 11 dirs | `elog-copilot/` |
|---|---|---|
| `cwang31` (owner) | rwx | rwx |
| `ps-users` members (~600 users) | r-x | — |
| `ps-agent` members (18 users, all also in ps-users) | r-x via group membership | r-x via ACL |
| Anyone else | — | — |

## Key facts captured during the session (for future reference)

- `cwang31` POSIX groups: `gu (1126), ps-users (10000), ps-data (2279)`. **Not** in `ps-agent`.
- `ps-agent ⊆ ps-users`: all 18 `ps-agent` members are also in `ps-users` as of 2026-04-23.
- `ps-agent-pub` / `ps-agent-plus` POSIX groups do **not** exist. References to them in older comments on issue #11 are hypothetical.
- `ps-user` (singular) does **not** exist. Older comments using that name refer to `ps-users` (plural) — this was a typo-in-practice, confirmed by the context in the live discussion.
- The setgid bit on the parent `/sdf/group/lcls/ds/dm/apps/dev/data/` keeps propagating `ps-data` as the group for newly-created subdirectories. That has not been changed.
