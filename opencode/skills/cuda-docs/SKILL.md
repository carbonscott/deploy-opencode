---
name: cuda-docs
description: Search NVIDIA CUDA documentation (Best Practices Guide, Runtime API, Driver API). Use for CUDA programming questions, API lookups, memory management, kernel optimization, streams, events, and GPU programming patterns.
---

# CUDA Documentation Search

Search CUDA 13.0 documentation stored as markdown files.

## Data Location

```
/sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs/
├── best-practices.md   # Optimization, profiling, memory patterns (2K lines)
├── runtime-api.md      # cudaMalloc, cudaMemcpy, streams, events (28K lines)
└── driver-api.md       # CU* low-level API, data types (34K lines)
```

## Document Overview

| File | Content | Use For |
|------|---------|---------|
| `best-practices.md` | CUDA C++ Best Practices Guide | Optimization strategies, memory coalescing, profiling, parallelization patterns |
| `runtime-api.md` | CUDA Runtime API Reference | `cuda*` functions (cudaMalloc, cudaMemcpy, cudaStream*, cudaEvent*) |
| `driver-api.md` | CUDA Driver API Reference | `CU*` types and `cu*` functions (lower-level control) |

## Search Workflow

1. Identify which doc(s) to search based on the query:
   - API function lookup → `runtime-api.md` (cuda*) or `driver-api.md` (CU*/cu*)
   - Best practices/optimization → `best-practices.md`
   - Unknown → search all

2. Use grep to find relevant sections:
```bash
# Case-insensitive search with context
grep -i -n -B2 -A10 "pattern" /sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs/FILE.md

# Search all docs
grep -i -n -B2 -A10 "pattern" /sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs/*.md
```

3. For API lookups, search for the function name directly:
```bash
grep -n -A20 "^cudaMalloc" /sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs/runtime-api.md
```

## Common Queries

| Query Type | Search Pattern | File |
|------------|----------------|------|
| Runtime API function | `grep -n -A20 "^cudaFunctionName"` | runtime-api.md |
| Driver API function | `grep -n -A20 "^cuFunctionName"` | driver-api.md |
| Data type | `grep -i -n -A5 "CUtypename"` | driver-api.md |
| Memory optimization | `grep -i -n -B2 -A10 "memory\|coalesce"` | best-practices.md |
| Streams/async | `grep -i -n -B2 -A10 "stream\|async"` | runtime-api.md, best-practices.md |

## Key Reminders

- Use `-i` for case-insensitive search
- Use `-n` to show line numbers for reference
- Use `-A` (after) and `-B` (before) for context
- Runtime API uses `cuda*` prefix; Driver API uses `cu*` prefix
- For broad topics, start with best-practices.md
