# Apptainer Security Sandbox for OpenCode

**Date:** 2026-03-13
**Status:** Implemented, testing
**Branch:** `feature/apptainer-sandbox`
**Related:** [apptainer-container-assessment.md](apptainer-container-assessment.md) (why we don't containerize the deployment itself), [apptainer-hybrid-container.md](apptainer-hybrid-container.md) (earlier hybrid proposal)

## Problem

The AI agent in OpenCode runs shell commands as the user's process with full user permissions. OpenCode's `permission` config in `opencode.json` blocks its own file operations, but any shell command (`bash`, `python`, compiled binary) bypasses these rules entirely. An agent could `rm -rf $HOME`, modify shared databases, delete SSH keys, or overwrite deployed skills — all with standard user permissions.

The previous assessment concluded that containerizing the *deployment* is a poor fit (too many bind mounts, cron complexity). This sandbox takes a different approach: containerize the *user session* to restrict what the agent can touch.

## Solution

Run OpenCode inside an Apptainer container with `--containall`. Every command the agent spawns inherits hard read-only restrictions enforced by the kernel. One-time startup cost, zero per-command overhead.

### Security model

| Writable | Read-only | Not visible |
|----------|-----------|-------------|
| `$PWD` (project dir) | `/sdf/group/lcls/ds/dm/apps/dev/` (shared tools/data) | `$HOME` (~/.ssh, creds, .bashrc) |
| `/tmp/$USER/opencode-sandbox/` (scratch) | `/usr`, `/lib64`, `/bin` (system tools) | Other users' directories |
| | `/opt/slurm/`, `/run/slurm/`, `/run/munge/` (Slurm) | `/sdf/scratch/` |
| | `/sdf/group/lcls/ds/ana/sw/conda1/` (Kerberos) | |
| | `/sdf/data/lcls/` (science data) | |

### Key design decisions

1. **Path preservation.** All bind mounts use identical host and container paths (`--bind /path:/path:ro`). Every skill, env.sh, and SKILL.md works without modification.

2. **$HOME is hidden.** `--containall` hides the real home directory. A writable scratch home at `/tmp/$USER/opencode-sandbox/home/` provides runtime state storage. `~/.gitconfig` is copied in so git commits have correct author info.

3. **Forced shared config.** `OPENCODE_CONFIG_DIR` is hardcoded to `/sdf/group/lcls/ds/dm/apps/dev/opencode` inside the sandbox, since the user's personal config dir (under `$HOME`) is not accessible.

4. **Cron jobs are unaffected.** They run on sdfcron001 outside any sandbox.

## Implementation

All files live in `sandbox/` in the deploy-opencode repo.

| File | Purpose |
|------|---------|
| `sandbox/opencode-sandbox.def` | Apptainer definition — minimal RockyLinux 9 (~43MB SIF) |
| `sandbox/build.sh` | Builds SIF with `--fakeroot` (works on S3DF without root) |
| `sandbox/deploy.sh` | Copies SIF + launcher to shared `/sdf/group/lcls/ds/dm/apps/dev/bin/` |
| `sandbox/bin/opencode-sandbox` | Launcher script — sets up bind mounts, env vars, scratch dirs |
| `sandbox/README.md` | User-facing documentation |

### The SIF image

Minimal RockyLinux 9 with only `coreutils-single` installed. It provides a root filesystem skeleton (`/`, `/dev`, `/proc`, `/sys`). All real tools come from host bind mounts. The image is 43MB and rarely needs rebuilding.

Building works with `--fakeroot` on S3DF (unprivileged user namespaces are enabled):

```bash
cd sandbox && ./build.sh
```

### The launcher

`sandbox/bin/opencode-sandbox` is a self-contained bash script. It:

1. Creates per-user scratch dirs under `/tmp/$USER/opencode-sandbox/`
2. Copies `~/.gitconfig` to the scratch home
3. Resolves the opencode binary at `/sdf/group/lcls/ds/dm/apps/dev/code/.opencode/bin/opencode` (the shell function wrapper is not available inside the container)
4. Builds the full `--bind` and `--env` argument lists
5. Execs into `apptainer run --containall`

Flags: `--data PATH` (extra RO mount), `--rw PATH` (extra RW mount), `--no-sandbox` (bypass), `--dry-run` (inspect command).

## Testing results (2026-03-13)

### Phase 0: Build

`apptainer build --fakeroot` works on S3DF. No external build infra needed.

### Phase 1: Core isolation

| Test | Result |
|------|--------|
| Write to shared deployment dir | **Blocked** — "Read-only file system" |
| Access `~/.ssh` | **Hidden** — "No such file or directory" |
| Write to `$PWD` | **OK** |
| Write to `/sdf/data/lcls/` (science data) | **Blocked** — "Read-only file system" |

### Phase 2: Tool verification

| Tool | Result | Notes |
|------|--------|-------|
| Slurm (`sinfo`) | **Works** | Required `/run/slurm` + `/var/spool/slurmd/conf-cache` (see issues below) |
| SQLite on elog DB | **Works** | Journal mode `delete` — no issues |
| SQLite on DAQ logs DB | **Fixed** | Journal mode `wal` — required `immutable=1` (see issues below) |
| git status/diff | **Works** | |
| git push | **Blocked (by design)** | SSH keys hidden |
| docs-index search | **Works** | After `immutable=1` fix and `UV_PYTHON_INSTALL_DIR` env var |
| lcat (lcls-catalog) | **Works** | |
| opencode binary | **Works** | Resolved via absolute path, prepended to PATH |

### Phase 3: Full OpenCode session

OpenCode launches successfully. Agent can read databases, query Slurm, edit files in `$PWD`. Tested `@daq-logs` skill after immutable fix.

## Issues discovered and fixed

### 1. `--env HOME=...` blocked by `--containall`

**Symptom:** Warning: "Overriding HOME environment variable with APPTAINERENV_HOME is not permitted"

**Cause:** Apptainer's `--containall` mode blocks HOME override via `--env`.

**Fix:** Use `--home /path` flag instead of `--env HOME=/path`.

### 2. Slurm config not found (configless mode)

**Symptom:** `sinfo: error: resolve_ctls_from_dns_srv: res_nsearch error: Unknown host`

**Cause:** S3DF runs Slurm 24.11 in configless mode. There is no `/etc/slurm/slurm.conf`. The actual config lives at `/run/slurm/conf/`, which is a symlink to `/var/spool/slurmd/conf-cache/`. The container had `/run/slurm/` mounted but the symlink target was missing.

**Fix:** Added `/var/spool/slurmd/conf-cache` to the bind mount list.

**Discovery method:** `strace -e trace=openat sinfo` revealed the config is read from `/run/slurm/conf/slurm.conf`.

### 3. SIF path resolution

**Symptom:** "Error: SIF not found: .../sandbox/bin/opencode-sandbox.sif"

**Cause:** The launcher looked for the SIF in `SCRIPT_DIR` (the `bin/` subdirectory), but the SIF lives one level up in `sandbox/`.

**Fix:** Changed to `SANDBOX_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"` and resolve SIF relative to that.

### 4. `opencode` command not found

**Symptom:** `exec: opencode: not found` inside the container.

**Cause:** On the host, `opencode` is a shell function defined in `~/.bashrc`. Shell functions are not available inside the container (no `.bashrc` sourced, `$HOME` hidden).

**Fix:** Resolve the binary directly at `/sdf/group/lcls/ds/dm/apps/dev/code/.opencode/bin/opencode` and prepend that directory to PATH inside the container.

### 5. SQLite WAL-mode databases fail on read-only mounts

**Symptom:** `Error: unable to open database file` for DAQ logs DB. Elog DB worked fine.

**Cause:** SQLite WAL mode requires creating `-wal` and `-shm` files alongside the database. On a read-only filesystem, this fails. Three of our databases use WAL mode:

| Database | Journal mode | Affected |
|----------|-------------|----------|
| elog-copilot.db | `delete` | No |
| daq_logs.db | `wal` | Yes |
| lcls-docs.db (confluence) | `delete` | No |
| closeout_notes.db (smartsheet) | `delete` | No |
| sdf-docs/search.db | `wal` | Yes |
| olcf-docs/search.db | `wal` | Yes |
| lcls2/.code-index.db | `delete` | No |
| smalldata_tools/.code-index.db | `delete` | No |

**Fix:** Use `immutable=1` flag when opening:
- sqlite3 CLI: `sqlite3 "file:///path/to/db?immutable=1"`
- Python: `sqlite3.connect(f"file:{path}?immutable=1", uri=True)`

Applied to: `daq-logs.md` agent, `docs-index` script (search and info functions only — index function needs write access).

### 6. `UV_PYTHON_INSTALL_DIR` not set

**Symptom:** `uv` tried to download Python into the sandbox scratch home and failed during extraction.

**Cause:** Without `UV_PYTHON_INSTALL_DIR`, `uv` defaults to `~/.local/share/uv/python/`. The scratch home is writable but the extraction failed (likely a space or permission issue in `/tmp`).

**Fix:** Added `UV_PYTHON_INSTALL_DIR=/sdf/group/lcls/ds/dm/apps/dev/python` to the container environment. This points `uv` to the pre-installed shared Python interpreters.

### 7. Stanford AI Gateway config not found

**Symptom:** OpenCode couldn't reach the API — config dir pointed to user's personal `~/.config/opencode/` which is hidden.

**Cause:** The launcher inherited `OPENCODE_CONFIG_DIR` from the user's shell environment, which pointed to their home directory.

**Fix:** Hardcode `OPENCODE_CONFIG_DIR="/sdf/group/lcls/ds/dm/apps/dev/opencode"` inside the sandbox. The shared config has the Stanford AI Gateway provider configured.

## Remaining work

- **Deploy to shared location:** Run `deploy.sh` to copy SIF + launcher to `/sdf/group/lcls/ds/dm/apps/dev/bin/`
- **User distribution:** Users add the shared `bin/` to PATH or define a shell function wrapper
- **Multi-user testing (Phase 4):** Second team member tests concurrent sessions
- **Performance:** First launch is slow (~5s Apptainer overhead). Subsequent launches on the same node are faster due to SIF page cache. The Stanford AI Gateway direct endpoint is slower than the local proxy on sdfcron001.
