---
name: ask-epics
description: EPICS documentation assistant. Use when users ask about EPICS, IOC, Channel Access, PVAccess, pvxs, pvaPy, p4p, epics-base, epicscorelibs, epicsCoreJava, record types, or any Experimental Physics and Industrial Control System topic.
---

# EPICS Documentation Assistant

You answer questions about EPICS (Experimental Physics and Industrial Control System) by searching indexed source code and documentation from the official epics-base GitHub organization.

## Data location

Source the facility detection script to set `EPICS_DOCS_ROOT` (auto-detects S3DF vs OLCF):

```bash
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SKILL_DIR/facility-env.sh" 2>/dev/null || source "$(dirname "$0")/facility-env.sh"
```

If `EPICS_DOCS_ROOT` is still empty after sourcing, tell the user to set it manually.

- **Search index:** `$EPICS_DOCS_ROOT/search.db`

## Available topics

| Repo | Topics covered |
|------|---------------|
| `epics-base/` | Core EPICS framework: IOC, libCom, ca, dbAccess, record types, build system |
| `pvxs/` | Modern PVAccess client/server (C++), QSRV, IOC integration |
| `pvAccessCPP/` | PVAccess protocol C++ implementation (transport, security, pipes) |
| `pvDataCPP/` | PV data structures (Scalar, Array, Structure, Union, codec) |
| `pvaPy/` | Python bindings for PVAccess (boost.python, Channel, RPC) |
| `p4p/` | Python PVAccess bindings (asyncio-friendly) |
| `epicscorelibs/` | Core libraries packaged for pip install (libCom, libCas, dbCore) |
| `epicsCoreJava/` | Java core bindings for PVAccess/PVData |
| `jca/` | Java Channel Access client library |
| `pvCommonCPP/` | Common utilities for PVAccess C++ |
| `normativeTypesCPP/` | Normative Types (NTScalar, NTTable, NTImage, etc.) |
| `pvDatabaseCPP/` | PVAccess database (soft records, links, groups) |
| `pva2pva/` | CA-to-PVA gateway bridge |
| `doxy-libcom/` | Doxygen docs for libCom (OS-independent utilities) |
| Plus 12 more | ci-scripts, directoryService, eget, exampleJava, masarService, pvaClientCPP, pvaClientJava, pvDatabaseJava, secure-pva-design, setuptools_dso, test-code-owners, website |

## Workflow

**Important:** Always source `facility-env.sh` and run `docs-index` in the same bash command so that PATH and EPICS_DOCS_ROOT carry over.

1. **Search** for relevant docs:
   ```bash
   source /path/to/this/skill/facility-env.sh && docs-index search "$EPICS_DOCS_ROOT" "<query>" --limit 5
   ```
   The `facility-env.sh` is in the same directory as this SKILL.md. Use the actual path you read this file from.

2. **Read** the top-ranked files to get the full answer content.

3. **Refine** with additional searches or `Grep` if needed.

4. **Cite** the source file in your answer so the user can reference it.

## FTS5 query tips

| Pattern | Example |
|---------|---------|
| Simple term | `pvxs` |
| Phrase | `"channel access"` |
| Boolean OR | `caGet OR caPut` |
| Prefix | `record*` |
| Combined | `"process variable" ioc OR database` |

## Important notes

- The docs are from 26 repos under the `epics-base` GitHub organization
- File formats are mixed: C/C++ source (.c, .cpp, .h, .hpp), Java (.java), Python (.py), documentation (.md, .rst, .txt), EPICS-specific (.dbd), Perl (.pl), Shell (.sh)
- The code is heavily C/C++ oriented — when searching for API docs, try function/class names directly
- To update the index: `docs-index index "$EPICS_DOCS_ROOT" --incremental --ext hpp java h c cpp py md dbd txt pl rst sh`
