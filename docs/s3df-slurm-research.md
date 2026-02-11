# S3DF Slurm Cluster Research

Research conducted 2026-02-08 from an interactive S3DF node (sdfiana025).
Slurm version: 24.11.3, RHEL 8.6 (kernel 4.18.0-372.32.1.el8_6.x86_64).

## Command Gotchas

Before running the commands in this doc, be aware of these pitfalls:

- **`sacctmgr show account where parent=X`** triggers an interactive Y/N prompt about `withassoc`. Pipe `echo "y" |` to avoid hanging.
- **`sacct -o AllocGRES`** was removed in Slurm 24.11. Use `AllocTRES` instead.
- **slurmdbd** (sdfslurmdb001:6819) is intermittently unavailable. Commands that depend on it (`sacctmgr`, `sacct`, `sshare`, `sreport`) may fail. Commands that work without it: `sinfo`, `squeue`, `scontrol`, `sprio`.
- **`sreport cluster AccountUtilizationByUser`** can overload the DB on large clusters. Use targeted queries instead.

## Cluster Topology

```bash
# Partition summary (nodes, CPUs, GRES, time limit)
sinfo -o "%P %D %c %G %l" -S %P

# Full partition config (AllowAccounts, AllowQos, MaxTime, etc.)
scontrol show partition

# Sample node detail (CPU model, memory, features, GRES)
scontrol show node sdfrome050
```

546 nodes, 9 partitions, 630 total GPUs.

| Partition | Nodes | CPU | GPUs/Node | GPU Model | CUDA | OS |
|-----------|-------|-----|-----------|-----------|------|----|
| roma (default) | 130 | AMD EPYC 7702 (Rome) 128c | -- | -- | -- | RHEL 8.6 |
| milano | 272 | AMD EPYC 7713 (Milan) 128c | -- | -- | -- | RHEL 8.6 |
| torino | 52 | AMD EPYC 9555 (Turin) 128c | -- | -- | -- | RHEL 9.6 |
| ampere | 42 | AMD EPYC 7542 (Rome) 128c | 4 | A100 40GB | 12.2 | RHEL 8.6 |
| turing | 26 | Intel Xeon 5118 (Skylake) 48c | 10 | RTX 2080 Ti 11GB | 12.2 | RHEL 8.6 |
| ada | 19 | AMD EPYC 9454 (Genoa) 96c | 10 | L40S 46GB | 12.2 | RHEL 8.6 |
| hopper | 3 | AMD EPYC 9575F (Turin) 256c | 4 | H200 141GB | 12.9 | RHEL 9.6 |
| test | 1 | -- | -- | -- | -- | -- |
| fermi-transfer | 1 | -- | -- | -- | -- | -- |

All partitions: MaxTime=10 days, DefaultTime=1 day, AllowAccounts=ALL, AllowQos=ALL.

### Effective CPUs Per Node (After CoreSpecCount)

```bash
# Per-node CPU detail (run for one representative node per partition)
scontrol show node <nodename> | grep -E "CPUAlloc|CPUEfctv|CPUTot|CoreSpecCount|CPUSpecList|ThreadsPerCore"
```

CoreSpecCount reserves cores for OS/Slurm daemons. Always request against CPUEfctv, not CPUTot.

| Partition | CPUTot | CoreSpec | CPUEfctv | HyperThreading |
|-----------|--------|----------|----------|----------------|
| roma | 128 | 8 | 120 | Off |
| milano | 128 | 8 | 120 | Off |
| torino | 128 | 8 | 120 | Off |
| ampere | 128 | 8 | 112 | On (2x) |
| turing | 48 | 4 | 40 | On (2x) |
| ada | 96 | 12 | 72 | On (2x) |
| hopper | 256 | 16 | 224 | On (2x) |

### Memory Per Node

```bash
# Memory + features per node in a partition
sinfo -p <partition> -N -o "%N %m %f" --noheader

# All nodes sorted by memory
sinfo -N -o "%N %P %m" --noheader | sort -k3 -n
```

| Partition | Allocatable Memory | Notes |
|-----------|--------------------|-------|
| roma | 480 GB | |
| milano | 480 GB (bulk), 1920 GB (4 nodes: sdfmilan269-272) | High-mem targetable via `--constraint="MEM_SZE:1920GB"` |
| torino | 720 GB | Uses `MEM_SIZE` (not `MEM_SZE`) |
| ampere | 952 GB | Best memory-to-GPU ratio (238 GB per GPU) |
| turing | 160 GB | |
| ada | 702 GB | |
| hopper | 1344 GB | |

### GPU GRES Syntax

```bash
# GRES names per GPU node
sinfo -p ampere,turing,ada,hopper -N -o "%N %G" --noheader

# TRES type IDs (gres/gpu variants)
sacctmgr show tres
```

| Partition | GRES Name | Example |
|-----------|-----------|---------|
| ampere | `gpu:a100` | `--gres=gpu:a100:1` |
| ada | `gpu:l40s` | `--gres=gpu:l40s:2` |
| turing | `gpu:geforce_rtx_2080_ti` | `--gres=gpu:geforce_rtx_2080_ti:1` |
| hopper | `gpu:h200` | `--gres=gpu:h200:1` |

Generic `--gres=gpu:1` also works on any GPU partition.

## Node Feature System

Every node advertises key:value feature tags usable with `--constraint`.

### Feature Taxonomy

```bash
# Features per node (sample)
sinfo -N -o "%N %P %f" --noheader | head -5

# Extract all unique feature keys across the cluster
sinfo -N -o "%f" --noheader | tr ',' '\n' | sort -u
```

| Category | Tags | Example Values |
|----------|------|----------------|
| CPU | `CPU_GEN`, `CPU_SKU`, `CPU_FRQ`, `CPU_MNF` | `CPU_GEN:MLN`, `CPU_SKU:7713`, `CPU_MNF:AMD` |
| GPU | `GPU_GEN`, `GPU_SKU`, `GPU_MEM`, `GPU_CC`, `GPU_DRV`, `GPU_CUDA` | `GPU_SKU:A100`, `GPU_CC:8.0`, `GPU_CUDA:12.2` |
| OS | `OS_ID`, `OS_VER` | `OS_ID:RHEL`, `OS_VER:8.6` |
| Memory | `MEM_SZE` (or `MEM_SIZE` on torino) | `MEM_SZE:480GB` |
| Security | `CrowdStrike_on`, `CrowdStrike_off` | (boolean-style, present/absent) |

### CrowdStrike and Node Weight System

```bash
# Weight + features per node (shows CrowdStrike correlation)
sinfo -p roma -N -o "%N %w %f" --noheader | head -5

# Weight distribution within a partition
sinfo -p roma -N -o "%N %w" --noheader | awk '{print $2}' | sort | uniq -c

# Which partitions have no CrowdStrike tag
sinfo -N -o "%N %P %f" --noheader | grep -v CrowdStrike | awk '{print $2}' | sort | uniq -c
```

The node weight system encodes a CrowdStrike-first scheduling policy:

| Weight | CrowdStrike | Partitions |
|--------|-------------|------------|
| 476 | ON (preferred) | roma (62 nodes), milano (20 nodes) |
| 676 | OFF (deferred) | roma (68 nodes), milano (252 nodes) |
| 56,117 | No tag | ada, hopper, torino, turing |
| 227,207 | No tag | ampere |

Slurm schedules lower-weight nodes first, so CrowdStrike-enabled nodes fill before CrowdStrike-off nodes.

- `--constraint=CrowdStrike_off` avoids the security agent overhead
- `--constraint=CrowdStrike_on` forces monitored nodes (compliance)
- GPU partitions do not carry CrowdStrike tags

### Known Inconsistency

Torino nodes use `MEM_SIZE:720GB` while all other partitions use `MEM_SZE:...`. Scripts using constraints must use the correct spelling for the target partition.

## Priority and Scheduling

### Priority Formula

```bash
scontrol show config | grep -i "PriorityWeight\|PriorityType\|PriorityDecay\|PriorityCalc\|PriorityMaxAge\|PriorityFavorSmall\|PriorityUsageReset\|FairShareDampen"
```

Plugin: `priority/multifactor`. Scheduler: `sched/backfill`.

```
Priority = (QOS * 100,000) + (FairShare * 10,000) + (JobSize * 1,000) + (Age * 100)
```

Partition weight = 0, Association weight = 0.

| Factor | Weight | Share of Priority |
|--------|--------|-------------------|
| QOS | 100,000 | 89.9% (dominant) |
| FairShare | 10,000 | 9.0% |
| JobSize | 1,000 | 0.9% |
| Age | 100 | 0.09% (negligible) |

QOS effectively creates hard tiers. Within a tier, fairshare is the tiebreaker.

### QOS Definitions

```bash
sacctmgr show qos format=Name%20,Priority,Preempt%30,PreemptMode%15,GraceTime,PreemptExemptTime,UsageFactor,Flags%30
```

| QOS | Priority | Preempts | Preempted By | PreemptMode | GracePeriod |
|-----|----------|----------|--------------|-------------|-------------|
| expedite | 100,000 | preemptable | -- | cluster | 0 |
| offline | 50,000 | -- | -- | cluster | 0 |
| normal | 10,000 | preemptable | -- | cancel | 0 |
| preemptable | 1 | -- | normal, expedite | within,cancel | **0** |

Priority ranges never overlap: expedite (~100k-111k) > offline (~50k-61k) > normal (~10k-21k) > preemptable (~1-11k).

### Preemption

```bash
# Preemptions in last 7 days by account (adjust dates)
sacct -S $(date -d '7 days ago' +%Y-%m-%dT00:00:00) -s PREEMPTED -o Account%40 -n | sort | uniq -c | sort -rn | head -20

# Currently running jobs by QOS
squeue -t RUNNING -o "%q" --noheader | sort | uniq -c | sort -rn
```

- Preemptable jobs are **cancelled** (not suspended, not requeued)
- **Zero grace period** -- can be killed immediately after starting
- ~18,900 preemptions in one week (Feb 1-7, 2026)
- Milano dominates: `shared:default@milano` had 11,787 preemptions
- ~30% of running jobs at any time are `preemptable` QOS
- Recommendation: trap SIGTERM, checkpoint regularly, use short tasks or job arrays

### Fairshare

```bash
# Fairshare tree (top-level accounts)
sshare -a -o Account%20,RawShares,NormShares,RawUsage,EffectvUsage,FairShare -n | head -40

# Fairshare with per-user detail
sshare -a -o Account%20,User%15,RawShares,NormShares,EffectvUsage,FairShare -n
```

- Algorithm: Classic half-life decay
- Half-life: **14 days** (usage halved every 14 days)
- Recalculation period: **5 minutes**
- Dampening factor: 1 (linear)
- No periodic hard reset

Top accounts by usage share (snapshot):

| Account | Usage Share | Notes |
|---------|------------|-------|
| shared | 63.6% | Catch-all, severely depressed fairshare |
| rubin | 14.9% | Vera Rubin Observatory |
| suncat | 10.0% | Catalysis research |
| lcls | 2.1% | Photon science |
| fermi | 1.6% | |
| simes | 1.4% | |

All ~41 top-level accounts have equal RawShares=1.

### Backfill Scheduler

```bash
scontrol show config | grep -i "SchedulerParameters\|SchedulerType"
```

| Parameter | Value | Meaning |
|-----------|-------|---------|
| bf_interval | 60s | Backfill runs every 60 seconds |
| bf_max_job_test | 1000 | Tests up to 1000 pending jobs per cycle |
| bf_max_job_user | 60 | Max 60 jobs tested per user per cycle |
| bf_resolution | 600s (10 min) | Time-slot granularity for gap-fitting |
| bf_continue | enabled | Keeps looking after first backfill found |
| sched_max_job_start | 1500 | Up to 1500 jobs started per cycle |
| pack_serial_at_end | enabled | Single-core jobs fill node fragments |

Shorter walltime requests (`--time`) significantly improve backfill chances.

## Resource Enforcement

### Cgroup

```bash
scontrol show config | grep -i "cgroup\|TaskPlugin"
# Also readable at /etc/slurm/cgroup.conf (if accessible)
```

- Plugin: `cgroup/v1`
- ConstrainCores: yes (CPU pinning enforced)
- ConstrainRAMSpace: yes (memory hard limit)
- AllowedSwapSpace: 0% (no swap permitted)
- ConstrainDevices: yes (GPU isolation via cgroup)

### Association Limits

```bash
scontrol show config | grep -i "AccountingStorageEnforce"
```

Enforcement: `associations,limits,qos`. All resource caps are at the account/association level (not QOS level).

Common limit types: `GrpTRES` (cpu, mem, gres/gpu, node counts per account per partition).

### Prolog/Epilog Lifecycle

```bash
# View the prolog/epilog scripts
cat /etc/slurm/prolog.d/50-prolog
cat /etc/slurm/epilog.d/50-epilog
cat /etc/slurm/tasks/prolog.sh
```

- **Prolog** (`/etc/slurm/prolog.d/50-prolog`): Creates `/lscratch/$USER/slurm_job_id_$JOBID`, enables loginctl linger, purges old lscratch if no other jobs on node
- **Epilog** (`/etc/slurm/epilog.d/50-epilog`): Cleans up `/lscratch/$USER` when last job on node finishes, disables loginctl linger
- **Task prolog** (`/etc/slurm/tasks/prolog.sh`): Sets `$LSCRATCH` environment variable for sbatch jobs

## Account Hierarchy

### Structure

```bash
# Top-level organizations
sacctmgr show account format=Account%30,Descr%50 where parent=root

# Sub-accounts of a specific org (note: pipe echo "y" to avoid interactive prompt)
echo "y" | sacctmgr show account where parent=lcls format=Account%30,Descr%50

# User count per org
sacctmgr show user -s format=User,Account -n | awk '{print $2}' | cut -d: -f1 | sort | uniq -c | sort -rn

# Associations with TRES limits for an org
sacctmgr show association account=lcls format=Account%40,Partition%15,QOS%30,GrpTRES%60 -n | head -40
```

30+ top-level organizations under `root`. Each org follows a three-tier meta-account pattern:

```
root
  +-- org (e.g., lcls, atlas, cryoem)
       +-- org:_all_                        (container, QOS=normal)
            +-- org:_regular_               (production workloads)
            |    +-- org:_regular_@partition (per-partition TRES limits)
            |         +-- org:experiment@partition (per-experiment limits)
            +-- org:_preemptable_           (opportunistic/overflow)
                 +-- org:default@partition  (fallback for users without experiment accounts)
```

- `_regular_` sub-accounts get `normal` + `preemptable` QOS (can run at full priority)
- `_preemptable_` sub-accounts get `preemptable` QOS only (can be cancelled anytime)
- `default` under `_preemptable_` is the fallback for users without explicit experiment associations
- Associations and TRES limits are stored per-partition

### Top-Level Organizations

| Org | Users | Description |
|-----|-------|-------------|
| lcls | 1,440 | Linac Coherent Light Source |
| rubin | 386 | Vera C. Rubin Observatory |
| ad | 365 | Accelerator Directorate |
| atlas | 296 | ATLAS detector at CERN |
| fermi | 175 | Fermi Gamma-ray Space Telescope |
| cryoem | 123 | Cryo-Electron Microscopy |
| facet | 94 | FACET-II accelerator test facility |
| mli | 78 | Machine Learning Initiative |
| kipac | 71 | Kavli Inst. for Particle Astrophysics |
| ssrl | 66 | Stanford Synchrotron Radiation Lightsource |
| ldmx | 33 | Light Dark Matter Experiment |
| scs | 25 | Scientific Computing |
| suncat | 24 | SUNCAT Center for Interface Science |

Additional orgs: shared, neutrino, supercdms, exo, rfar, hps, fpd, simes, rp, epptheory, topas, desc, cds, faders, s3dfadmin, plus test accounts.

### Org-Wide Partition Caps (_regular_ level)

Each org has different "home" partitions with normal-QOS access. Not all orgs have equal access.

| Org | Milano (nodes) | Roma (nodes) | Ampere (nodes) | Other |
|-----|---------------|-------------|---------------|-------|
| LCLS | **88** | **22** | **4** | ada: preemptable only |
| Fermi | **20** | **16** | -- | |
| Rubin | unlimited | **8** | preemptable | ada: normal |
| Atlas | preemptable | normal | normal | turing: normal |
| CryoEM | preemptable | normal | normal | turing+ada: normal |
| AD | normal | preemptable | **2** | |
| MLI | preemptable | preemptable | preemptable | turing: **11** |

### LCLS Experiment Naming Convention

~693 experiment sub-accounts under LCLS. Names encode **instrument** + **experiment ID**:

| Prefix | Instrument | Count |
|--------|-----------|-------|
| mfx | Macromolecular Femtosecond X-ray | 131 |
| cxi | Coherent X-ray Imaging | 99 |
| xcs | X-ray Correlation Spectroscopy | 88 |
| xpp | X-ray Pump Probe | 84 |
| mec | Matter in Extreme Conditions | 75 |
| rix | Resonant Inelastic X-ray Scattering | 56 |
| tmo | Time-resolved Molecular Orbital | 55 |
| ued | Ultrafast Electron Diffraction | 36 |
| amo | Atomic Molecular Optical | 15 |
| txi | TXI | 7 |

Additional non-experiment accounts: `prj*` (24, long-lived projects), `det*` (detector), `asc*` (DAQ), `data` (service).

ID variants: short IDs = LCLS-I era (e.g., `cxi65913`), `l` prefix = LCLS-II (e.g., `cxil1002722`), long 9-digit IDs = proposal-based (e.g., `cxi100862824`).

### LCLS Per-Experiment TRES Limits

Standard tiers for LCLS experiments:

**Milano:**

| Tier | CPU | Memory | Nodes | Experiments |
|------|-----|--------|-------|-------------|
| Standard | 2,112 | 8,448G | 18 | 576 |
| Small | 1,056 | 4,224G | 9 | 101 |
| Large | 8,448 | 33T | 71 | 5 |

**Roma:**

| Tier | CPU | Memory | Nodes | Experiments |
|------|-----|--------|-------|-------------|
| Standard | 528 | 2,112G | 5 | 239 |
| Small | 264 | 1,056G | 3 | 10 |

**Ampere:**

| Tier | CPU | Memory | GPUs | Nodes | Experiments |
|------|-----|--------|------|-------|-------------|
| Standard | 96 | 768G | 3 | 1 | 235 |
| Enhanced | 120 | 960G | 4 | 1 | 2 |

**Ada:** Most LCLS experiments get preemptable-only access. A few privileged experiments get `cpu=58, gres/gpu=8, mem=562G, node=1` with normal QOS.

## Pending Job Analysis (Snapshot)

```bash
# Pending reasons breakdown
squeue -t PD -o "%r" --noheader | sort | uniq -c | sort -rn

# Pending by user/account/partition/reason
squeue -t PD -o "%u %a %P %r" --noheader | sort -k4 | head -30

# Total job counts (all, running, pending)
squeue --noheader | wc -l && squeue -t RUNNING --noheader | wc -l && squeue -t PENDING --noheader | wc -l

# Total cores consumed by running jobs
squeue -t RUNNING -o "%C" --noheader | awk '{sum+=$1} END {print sum}'
```

Of ~1,249 pending jobs:

| Reason | Count | % | Interpretation |
|--------|-------|---|----------------|
| AssocGrpNodeLimit | 934 | 74.8% | Account hit node cap |
| AssocGrpCpuLimit | 114 | 9.1% | Account hit CPU cap |
| Priority | 62 | 5.0% | Lower priority than running jobs |
| AssocGrpMemLimit | 51 | 4.1% | Account hit memory cap |
| AssocMaxJobsLimit | 3 | 0.2% | Account hit max concurrent jobs |
| Resources | 2 | 0.2% | Actual hardware scarcity |
| launch failed requeued held | 2 | 0.2% | Stuck, needs manual release |

**88% of pending jobs are blocked by association limits, not resource scarcity.** Only 2 jobs were waiting for physical hardware.

## GPU Utilization (Snapshot)

```bash
# GPU node states
sinfo -p ampere,turing,ada,hopper -N -o "%N %P %G %T" --noheader

# Per-node GPU allocation (check AllocTRES for gres/gpu count)
scontrol show node sdfampere001 | grep -E "AllocTRES|Gres "

# Node allocation summary per partition (alloc/idle/other/total)
sinfo -o "%P %F" --noheader
```

At time of research, GPU utilization was effectively **100% across all active nodes**. All 532 operational GPUs were allocated.

| Partition | Total GPUs | Active Nodes | Down/Drained Nodes | GPUs Lost | % Capacity Lost |
|-----------|-----------|-------------|--------------------|-----------|-----------------|
| hopper | 12 | 3 | 0 | 0 | 0% |
| ampere | 168 | 35 | 7 | 28 | 16.7% |
| ada | 190 | 18 | 1 | 10 | 5.3% |
| turing | 260 | 20 | 6 | 60 | 23.1% |

### Per-Account GPU Limits (Selected)

```bash
# All associations with GPU limits
sacctmgr show association format=Account%40,Partition%15,GrpTRES%60 -n | grep "gres/gpu"
```

| Account | Partition | GPU Limit | Notes |
|---------|-----------|-----------|-------|
| lcls:data | ampere | 16 | 4 nodes |
| lcls (per experiment) | ampere | 3 | 1 node |
| lcls (per experiment) | turing | 2 | 1 node |
| cryoem:daq | ada | 100 | 10 nodes (largest allocation) |
| cryoem:daq | turing | 120 | 12 nodes |
| cryoem (per experiment) | ampere | 10 | 3 nodes |
| atlas:compef | ampere | 8 | 3 nodes |
| kipac:kipac | ada | 5 | 1 node |

## Node Health Issues

```bash
# Down/drained nodes with reason and timestamp
sinfo -R -o "%N %E %H" --noheader

# Node allocation summary per partition (alloc/idle/other/total)
sinfo -o "%P %F" --noheader

# Filesystem-related node failures
sinfo -R -o "%N %E" --noheader | grep filesystem
```

### Prolonged Outages

| Node(s) | Days Down | Reason |
|---------|-----------|--------|
| sdfrome070 | 122 | bad_IPMI |
| sdfrome001 | 88 | Not responding |
| sdfrome032 | 86 | Not responding |
| sdfampere005,007,022 | 54 | bad_hw |
| sdfturing010 | 50 | bad_gpu |
| sdfmilan112 | 48 | bad_hw |

### Active Issues (2026-02-08)

Multiple nodes across ampere, turing, and milano failing autochecks for `filesystem-fs-weka-sdfdata-s3ai`, indicating a systemic Weka/S3AI storage issue.

## Filesystem Mounts

```bash
df -hT | grep -E "sdf|lscratch"
cat /etc/profile.d/scratch.sh    # sets $SCRATCH
cat /etc/slurm/tasks/prolog.sh   # sets $LSCRATCH
```

| Mount | Type | Purpose |
|-------|------|---------|
| /sdf/home | Weka | Home directories |
| /sdf/scratch | Weka | Scratch space ($SCRATCH) |
| /sdf/data | Weka | Project data |
| /lscratch | Local NVMe | Per-job local scratch (managed by prolog/epilog) |

`$SCRATCH` set by `/etc/profile.d/scratch.sh` to `/sdf/scratch/users/${USER:0:1}/$USER`.
`$LSCRATCH` set by task prolog to `/lscratch/$USER/slurm_job_id_$SLURM_JOB_ID`.

## Reservations (Snapshot)

```bash
scontrol show reservation
```

| Reservation | Nodes | Purpose |
|-------------|-------|---------|
| hardware_repairs | sdfrome070 | Long-term hardware fix |
| donotresurrect | sdfrome001,024,032 | Nodes flagged for decommission/repair |
| lcls:onshift | sdfmilan[101-110] | LCLS beamline on-shift reservation |

## Common User Queries

Commands for answering frequent questions:

```bash
# "Why is my job pending?"
scontrol show job <jobid>          # full job detail including Reason
squeue -u $USER -t PD -o "%i %r"  # all my pending jobs with reasons
sprio -u $USER -n -l              # priority breakdown for my pending jobs

# "What are my account limits?"
sacctmgr show association where user=$USER format=Account%30,Partition%15,QOS%30,GrpTRES%40 -n

# "What is my fairshare?"
sshare -u $USER

# "Which partitions have idle resources?"
sinfo -o "%P %F %C" --noheader    # alloc/idle/other/total nodes and CPUs

# "What GPU resources are available?"
sinfo -p ampere,turing,ada,hopper -N -o "%N %G %T %C" --noheader

# "How long has my job been running?"
squeue -u $USER -t RUNNING -o "%i %j %M %l %P"  # elapsed vs time limit

# "What happened to my completed job?"
sacct -j <jobid> -o JobID,State,ExitCode,Elapsed,MaxRSS,AllocTRES%60
```

## Context Gaps for AI Assistance

### Fully Accessible (AI can answer today)

- Why is my job pending?
- Which partition should I use?
- How do I request GPUs?
- What is my priority/fairshare?
- Is the cluster healthy?
- Job template generation

### Partially Accessible

- Job history and efficiency analysis (depends on slurmdbd availability)
- Account hierarchy details (sacctmgr queries intermittently fail)

### Not Accessible

- Production `job_submit.lua` rules (not world-readable)
- Account request procedures (site policy, not in Slurm)
- Open OnDemand portal configuration
- Network/storage topology details
- Module compatibility matrices

### How to Bridge the Gaps

1. Make `job_submit.lua` readable (or provide a summary of its rules)
2. Provide a short FAQ covering account request procedures
3. Link to site user documentation

With these three additions, AI would cover >95% of first-line Slurm support questions.
