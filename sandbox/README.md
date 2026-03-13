# Apptainer Security Sandbox for OpenCode

Kernel-level filesystem isolation for OpenCode on S3DF. Runs OpenCode inside an Apptainer container so every command the AI agent spawns inherits hard read-only restrictions — preventing accidental or malicious writes to shared infrastructure, databases, SSH keys, or home directory.

## What the sandbox protects

| Writable | Read-only | Not visible |
|----------|-----------|-------------|
| `$PWD` (your project dir) | `/sdf/group/lcls/ds/dm/apps/dev/` (shared tools/data) | `$HOME` (~/.ssh, credentials, .bashrc) |
| `/tmp/$USER/opencode-sandbox/` (scratch) | `/usr`, `/lib64`, `/bin` (system tools) | Other users' directories |
| | `/opt/slurm/`, `/run/slurm/`, `/run/munge/` (Slurm) | `/sdf/scratch/` |
| | `/sdf/group/lcls/ds/ana/sw/conda1/` (Kerberos) | |
| | `/sdf/data/lcls/` (science data) | |

## Quick start

```bash
# 1. Build the SIF image (one-time)
cd sandbox/
./build.sh

# 2. Deploy to shared location (maintainer only)
./deploy.sh

# 3. Run OpenCode in the sandbox
opencode-sandbox

# Or from the source directory
sandbox/bin/opencode-sandbox
```

## Usage

```bash
# Basic launch — sandbox on, $PWD is writable
opencode-sandbox

# Add extra read-only data paths
opencode-sandbox --data /sdf/data/lcls/ds/prj/myproject/

# Add extra read-write paths (use sparingly)
opencode-sandbox --rw /sdf/scratch/users/$USER/workdir/

# See the apptainer command without running it
opencode-sandbox --dry-run

# Bypass sandbox entirely (no protection)
opencode-sandbox --no-sandbox

# Pass arguments through to opencode
opencode-sandbox -- --some-opencode-flag
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCODE_SANDBOX_SIF` | `<script-dir>/opencode-sandbox.sif` | Path to the SIF image |
| `OPENCODE_SANDBOX_EXTRA` | (none) | Colon-separated extra read-only paths |
| `OPENCODE_CONFIG_DIR` | `/sdf/group/lcls/ds/dm/apps/dev/opencode` | OpenCode config directory |

## Design notes

- **Path preservation**: All host paths are identical inside the container. No path rewriting needed in skills, agents, or env.sh files.
- **$HOME is hidden**: `--containall` hides the real home. A fake writable home at `/tmp/$USER/opencode-sandbox/home/` stores runtime state. This means `git push` and SSH fail — this is intentional security behavior.
- **Git commits work**: `~/.gitconfig` is copied to the scratch home so author info is correct. But pushes require SSH keys (hidden), so you push after exiting the sandbox.
- **Slurm works**: Slurm binaries, config, and munge socket are mounted read-only. Network is not isolated, so daemon communication works.
- **SQLite reads work**: Databases on read-only mounts open in read-only mode. Cron jobs (running outside the sandbox on sdfcron001) handle all writes.
- **Cron jobs are unaffected**: They run on sdfcron001 outside any sandbox.

## Building the SIF

The SIF image is a minimal RockyLinux 9 filesystem skeleton (~50-80 MB). All real tools come from host bind mounts.

```bash
# On S3DF (if --fakeroot works)
./build.sh

# On a machine with root access (fallback)
sudo apptainer build opencode-sandbox.sif opencode-sandbox.def
scp opencode-sandbox.sif s3dflogin.slac.stanford.edu:<path>/sandbox/
```

The SIF rarely needs rebuilding since it's just a filesystem skeleton.

## Known limitations

1. **No git push/SSH**: Home directory (with SSH keys) is hidden. Push changes after exiting the sandbox.
2. **No writes to shared deployment**: `/sdf/group/lcls/ds/dm/apps/dev/` is read-only. Deploy changes from outside the sandbox.
3. **SQLite WAL mode**: If a database is mid-write by a cron job while you read it, you may get a brief lock. In practice this is rare and resolves quickly.
4. **OpenCode state**: OpenCode writes runtime state to `$HOME`. The sandbox provides a writable scratch home, but state does not persist across sandbox sessions. If persistence is needed, mount a specific path with `--rw`.
5. **New paths**: If a skill references a path not in the default bind list, add it with `--data PATH`.

## Testing checklist

```bash
# Phase 0: Can we build?
./build.sh

# Phase 1: Basic isolation
apptainer run --containall opencode-sandbox.sif bash
touch /sdf/group/lcls/ds/dm/apps/dev/test   # should fail: Read-only
ls ~/.ssh                                      # should fail: no such file
touch ./test-write                             # should succeed

# Phase 2: Tool verification
sinfo -N | head                                # Slurm works
sqlite3 /sdf/group/lcls/ds/dm/apps/dev/data/elog-copilot/elog-copilot.db "SELECT count(*) FROM runs"
git status                                     # works in $PWD
which opencode                                 # found via PATH

# Phase 3: Full OpenCode session
opencode-sandbox
# Inside: ask agent to read elog data, query Slurm, edit a file

# Phase 4: Multi-user
# Have a second team member run opencode-sandbox concurrently
```
