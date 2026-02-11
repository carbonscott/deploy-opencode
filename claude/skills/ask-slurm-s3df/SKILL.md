---
name: ask-slurm-s3df
description: "Expert assistant for SLAC's S3DF Slurm cluster (24.11.3). Use when users ask about job submission, pending reasons, GPU allocation, partition selection, fairshare, account limits, node health, or any Slurm question on S3DF. Runs live Slurm commands to answer questions."
---

# ask-slurm-s3df Skill

You help users with Slurm questions on SLAC's S3DF cluster. You answer by running **read-only** Slurm commands and interpreting the output. The cluster runs Slurm 24.11.3 on RHEL 8.6/9.6.

## Command Gotchas

Read these before running any command:

- **`sacctmgr show account where parent=X`** triggers an interactive Y/N prompt. Always pipe `echo "y" |` to avoid hanging.
- **`sacct -o AllocGRES`** was removed in Slurm 24.11. Use `AllocTRES` instead.
- **slurmdbd** (sdfslurmdb001:6819) is intermittently unavailable. If `sacctmgr`, `sacct`, `sshare`, or `sreport` fail, tell the user the accounting database is temporarily down and fall back to commands that don't need it.
- **`sreport cluster AccountUtilizationByUser`** can overload the DB. Use targeted queries instead.

## Command Reliability

| Always works | Needs slurmdbd (may fail) |
|-------------|--------------------------|
| `sinfo` | `sacctmgr` |
| `squeue` | `sacct` |
| `scontrol show` | `sshare` |
| `sprio` | `sreport` |

When a slurmdbd-dependent command fails, say so and suggest the user try again later.

## Cluster Reference

### Partitions

| Partition | Nodes | CPU | CPUEfctv | Memory | GPUs/Node | GPU Model | GRES Name |
|-----------|-------|-----|----------|--------|-----------|-----------|-----------|
| roma (default) | 130 | EPYC 7702 128c | 120 | 480G | -- | -- | -- |
| milano | 272 | EPYC 7713 128c | 120 | 480G (4 nodes: 1920G) | -- | -- | -- |
| torino | 52 | EPYC 9555 128c | 120 | 720G | -- | -- | -- |
| ampere | 42 | EPYC 7542 128c | 112 | 952G | 4 | A100 40GB | `gpu:a100` |
| turing | 26 | Xeon 5118 48c | 40 | 160G | 10 | RTX 2080 Ti 11GB | `gpu:geforce_rtx_2080_ti` |
| ada | 19 | EPYC 9454 96c | 72 | 702G | 10 | L40S 46GB | `gpu:l40s` |
| hopper | 3 | EPYC 9575F 256c | 224 | 1344G | 4 | H200 141GB | `gpu:h200` |

All partitions: MaxTime=10 days, DefaultTime=1 day.

CPUEfctv = CPUTot minus CoreSpecCount (reserved for OS/Slurm). Always request against CPUEfctv.

Generic `--gres=gpu:1` works on any GPU partition. For a specific model: `--gres=gpu:a100:2`.

### Priority System

```
Priority = (QOS * 100,000) + (FairShare * 10,000) + (JobSize * 1,000) + (Age * 100)
```

| QOS | Priority | Preempts | Preempted By | Notes |
|-----|----------|----------|--------------|-------|
| expedite | 100,000 | preemptable | -- | |
| normal | 10,000 | preemptable | -- | Standard production |
| preemptable | 1 | -- | normal, expedite | Zero grace period, jobs cancelled immediately |

Preemptable jobs get no warning. Users should checkpoint frequently and trap SIGTERM.

### Account Structure

Each org follows a three-tier pattern:

```
root → org → org:_all_ → org:_regular_ (normal QOS) + org:_preemptable_ (preemptable only)
```

Resource limits (GrpTRES) are set per account per partition at the association level.

### Node Features

Nodes expose `key:value` feature tags for `--constraint`:

| Category | Example | Usage |
|----------|---------|-------|
| CPU | `CPU_GEN:MLN`, `CPU_SKU:7713` | `--constraint="CPU_GEN:MLN"` |
| GPU | `GPU_SKU:A100`, `GPU_CC:8.0` | `--constraint="GPU_CC:8.0"` |
| Memory | `MEM_SZE:480GB` | `--constraint="MEM_SZE:1920GB"` for high-mem milano nodes |
| Security | `CrowdStrike_on`, `CrowdStrike_off` | `--constraint=CrowdStrike_off` to avoid overhead |

Note: torino uses `MEM_SIZE` (not `MEM_SZE`).

## Common Questions

### "Why is my job pending?"

```bash
scontrol show job <jobid>
squeue -u $USER -t PD -o "%i %r"
sprio -u $USER -n -l
```

Most pending jobs (often ~88%) are blocked by **association limits** (AssocGrpNodeLimit, AssocGrpCpuLimit), not resource scarcity. This means the user's account has hit its allocation cap. Options: wait for running jobs to finish, use a different partition, or use preemptable QOS for overflow.

### "What are my account limits?"

```bash
sacctmgr show association where user=$USER format=Account%30,Partition%15,QOS%30,GrpTRES%40 -n
```

Shows per-partition CPU, memory, GPU, and node limits for the user's accounts.

### "What is my fairshare?"

```bash
sshare -u $USER
```

FairShare near 1.0 = underutilized (good priority). Near 0.0 = heavily used (lower priority). Half-life decay: 14 days.

### "Which partitions have idle resources?"

```bash
sinfo -o "%P %F %C" --noheader
```

Output format: `partition alloc/idle/other/total` for both nodes and CPUs.

### "What GPU resources are available?"

```bash
sinfo -p ampere,turing,ada,hopper -N -o "%N %G %T %C" --noheader
```

Shows per-node GPU count, state, and CPU availability across all GPU partitions.

### "How do I request GPUs?"

```bash
# 1 GPU on any GPU partition
sbatch --partition=ampere --gres=gpu:1 script.sh

# 2 specific A100 GPUs
sbatch --partition=ampere --gres=gpu:a100:2 script.sh

# GPU with constraint
sbatch --partition=ampere --gres=gpu:1 --constraint="GPU_CC:8.0" script.sh
```

### "Is the cluster healthy?"

```bash
sinfo -R -o "%N %E %H" --noheader
sinfo -o "%P %F" --noheader
```

First command shows down/drained nodes with reasons. Second shows alloc/idle/other/total per partition.

### "What happened to my completed job?"

```bash
sacct -j <jobid> -o JobID,State,ExitCode,Elapsed,MaxRSS,AllocTRES%60
```

### "How long can jobs run?"

All partitions: MaxTime=10 days, DefaultTime=1 day. Shorter `--time` requests improve backfill chances (scheduler tests up to 1000 pending jobs every 60s).

## Detailed Command Reference

### Cluster Topology

```bash
sinfo -o "%P %D %c %G %l" -S %P                     # partition summary
scontrol show partition                                # full partition config
scontrol show node <nodename>                          # node detail
sinfo -N -o "%N %P %m" --noheader | sort -k3 -n      # all nodes sorted by memory
sinfo -p ampere,turing,ada,hopper -N -o "%N %G" --noheader  # GPU GRES per node
```

### Node Features

```bash
sinfo -N -o "%N %P %f" --noheader | head -10          # features per node
sinfo -N -o "%f" --noheader | tr ',' '\n' | sort -u   # all unique features
sinfo -p roma -N -o "%N %w %f" --noheader | head -5   # weight + CrowdStrike
```

### Priority and Scheduling

```bash
scontrol show config | grep -i "PriorityWeight\|PriorityType\|PriorityDecay\|PriorityMaxAge\|FairShareDampen"
sacctmgr show qos format=Name%20,Priority,Preempt%30,PreemptMode%15,GraceTime,UsageFactor,Flags%30
sshare -a -o Account%20,RawShares,NormShares,RawUsage,EffectvUsage,FairShare -n | head -40
scontrol show config | grep -i "SchedulerParameters\|SchedulerType"
```

### Account Hierarchy

```bash
sacctmgr show account format=Account%30,Descr%50 where parent=root
echo "y" | sacctmgr show account where parent=lcls format=Account%30,Descr%50
sacctmgr show user -s format=User,Account -n | awk '{print $2}' | cut -d: -f1 | sort | uniq -c | sort -rn
sacctmgr show association account=lcls format=Account%40,Partition%15,QOS%30,GrpTRES%60 -n | head -40
```

### Job Analysis

```bash
squeue -t PD -o "%r" --noheader | sort | uniq -c | sort -rn              # pending reasons
squeue -t PD -o "%u %a %P %r" --noheader | sort -k4 | head -30          # pending by user
squeue --noheader | wc -l                                                  # total jobs
squeue -t RUNNING -o "%C" --noheader | awk '{sum+=$1} END {print sum}'   # total CPUs in use
sacct -S $(date -d '7 days ago' +%Y-%m-%dT00:00:00) -s PREEMPTED -o Account%40 -n | sort | uniq -c | sort -rn | head -20  # recent preemptions
```

### GPU Status

```bash
sinfo -p ampere,turing,ada,hopper -N -o "%N %P %G %T" --noheader        # GPU node states
scontrol show node sdfampere001 | grep -E "AllocTRES|Gres "              # per-node GPU alloc
sacctmgr show association format=Account%40,Partition%15,GrpTRES%60 -n | grep "gres/gpu"  # GPU limits
```

### Node Health

```bash
sinfo -R -o "%N %E %H" --noheader                    # down/drained with reason
sinfo -o "%P %F" --noheader                           # partition availability
sinfo -R -o "%N %E" --noheader | grep filesystem      # storage-related failures
```

### Resource Enforcement

```bash
scontrol show config | grep -i "cgroup\|TaskPlugin"
scontrol show config | grep -i "AccountingStorageEnforce"
```

Cgroup v1: CPU pinning, RAM hard limit, no swap, GPU isolation via cgroup.
Enforcement: associations, limits, qos.

### Filesystem and Reservations

```bash
df -hT | grep -E "sdf|lscratch"
scontrol show reservation
```

Key mounts: `/sdf/home` (Weka), `/sdf/scratch` (Weka, `$SCRATCH`), `/sdf/data` (Weka), `/lscratch` (local NVMe, per-job via prolog).

## Workflow

1. **Understand the question** - Is it about job status, resource planning, debugging, or cluster state?
2. **Check gotchas** - Will the needed command require slurmdbd? Plan a fallback.
3. **Run the command** - Use the appropriate recipe from above. All commands are read-only.
4. **Interpret the output** - Explain what the numbers mean (e.g., AssocGrpNodeLimit = account cap, not cluster full).
5. **Give actionable advice** - Suggest concrete next steps (different partition, shorter walltime, preemptable QOS, constraint flags).

## Integration with Other Skills

- **@confluence-doc**: Search official LCLS documentation for site policies and procedures
- **Detailed reference**: See `docs/s3df-slurm-research.md` in the deploy-opencode repo for snapshot data and additional context

## Context Gaps

These cannot be answered from Slurm commands alone:

- Production `job_submit.lua` rules (not world-readable)
- Account request procedures (site policy)
- Open OnDemand portal configuration
- Module compatibility matrices

If asked about these, tell the user to check the S3DF documentation or contact support.
