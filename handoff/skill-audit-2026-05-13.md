# Knowledge-wrapper skill audit (2026-05-13)

Read-only audit before Phase 2. Establishes per-skill source-of-truth, current remote layout, cron status, and discrepancies with `handoff/skill-inventory.md`.

## Total in scope: 15 knowledge wrappers

The user's earlier "13" was wrong — the inventory lists 15. All are in scope per "All knowledge wrappers" answer.

## Per-skill state

| # | Skill | In repo `claude/skills/` | In repo `opencode/skills/` | Deployed `opencode/skills/` | GitHub remote | Cron (host: sdfcron001) |
|---|---|---|---|---|---|---|
| 1 | ask-ami | SKILL.md | SKILL.md | SKILL.md | none | none |
| 2 | ask-lcls2 | SKILL.md | SKILL.md | SKILL.md | none | none (manual `update-index.sh`) |
| 3 | ask-smalldata | SKILL.md | SKILL.md | SKILL.md | none | none (manual `update-index.sh`) |
| 4 | cuda-docs | SKILL.md | SKILL.md | SKILL.md | none | none (static md files) |
| 5 | experimental-hutch-python | SKILL.md + scripts + references | SKILL.md + scripts + references | SKILL.md + scripts + references | none | none |
| 6 | askcode | SKILL.md | SKILL.md | SKILL.md | `carbonscott/skill-askcode` (flat layout: SKILL.md, README.md, env.sh) | none (on-demand `tsdb`) |
| 7 | docs-search | SKILL.md + scripts + facility-env.sh | SKILL.md | SKILL.md + facility-env.sh | `carbonscott/skill-docs-search` (flat: SKILL.md, README.md, bin, env.sh) | none |
| 8 | ask-slurm-s3df | SKILL.md | SKILL.md | SKILL.md | `carbonscott/skill-ask-slurm-s3df` (flat: SKILL.md, README.md) | none |
| 9 | ask-olcf | SKILL.md | (missing) | SKILL.md + bin + env.local + env.sh + setup.sh | `carbonscott/skill-ask-olcf` (flat: SKILL.md, bin, env.sh, setup.sh, tools) | **none** (inventory said weekly — inventory is wrong) |
| 10 | ask-s3df | (empty) | SKILL.md | SKILL.md + bin + env.local + env.sh + setup.sh | `carbonscott/skill-ask-s3df` (flat: SKILL.md, bin, env.sh, setup.sh, tools) | sdf-docs sync **hourly** (inventory said daily — wrong) |
| 11 | ask-epics | (empty) | (empty) | SKILL.md + bin + env.local + env.sh + setup.sh | `carbonscott/skill-ask-epics` (flat + tools) | epics-docs sync weekly Sun 3am ✓ |
| 12 | ask-nersc | (empty) | (empty) | SKILL.md + bin + env.local + env.sh + setup.sh | `carbonscott/skill-ask-nersc` (flat + tools) | nersc-docs sync weekly Sun 3am (inventory said none — wrong) |
| 13 | ask-tiled | (empty) | (empty) | SKILL.md + bin + env.local + env.sh + setup.sh | `carbonscott/skill-ask-tiled` (flat + tools) | tiled-docs sync weekly Sun 3am (inventory said none — wrong) |
| 14 | ask-slac-ai-tools | (empty) | (empty) | SKILL.md + data + env.local + env.sh + schemas + scripts + setup.sh | `carbonscott/ask-slac-ai-tools` (flat: SKILL.md, data, env.sh, schemas, scripts, setup.sh) — **needs rename to skill-ask-slac-ai-tools** | none |
| 15 | xpm-seq | (empty) | (empty) | README.md + SKILL.md + bin + env.sh + references | `carbonscott/xpm-seq-skills` (flat: README.md, SKILL.md, bin, env.sh, references) — **needs rename to skill-xpm-seq** | none |

## Source-of-truth resolution

The **deployed copy** at `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/<name>/` is the ground truth for all 15 wrappers — it's the most complete and is what users actually run against. The worktree's `claude/skills/` and `opencode/skills/` directories are partial/stale sketches that have drifted from the deployed copies (some empty, some missing files like `env.sh` / `setup.sh` / `bin/`).

**Implication for extraction**: each skill's content should be sourced from the deployed copy (`/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/<name>/`), not the worktree's `claude/skills/<name>/` or `opencode/skills/<name>/`. For 10 of them, the existing GitHub remote is also a valid source — but those are **flat** layout, so we'd still need to restructure into `claude/+opencode/`.

## Cron status — corrected

| Skill | Cron source | Schedule | Inventory claim | Reality |
|---|---|---|---|---|
| skill-ask-epics | `tools/epics-docs/scripts/epics-docs-cron.sh` | weekly Sun 3am | weekly | ✓ |
| skill-ask-nersc | `tools/nersc-docs/scripts/nersc-docs-cron.sh` | weekly Sun 3am | none | **inventory wrong** — has cron |
| skill-ask-olcf | `tools/olcf-docs/` exists, no crontab entry | none | weekly | **inventory wrong** — cron deployed but not scheduled |
| skill-ask-s3df | `tools/sdf-docs/scripts/sdf-docs-cron.sh` | **hourly** | daily | **inventory wrong** — actually hourly |
| skill-ask-tiled | `tools/tiled-docs/scripts/tiled-docs-cron.sh` | weekly Sun 3am | none | **inventory wrong** — has cron |
| others | n/a | none | none | ✓ |

Cron tool dirs deployed at `/sdf/group/lcls/ds/dm/apps/dev/tools/`: `epics-docs`, `nersc-docs`, `olcf-docs`, `sdf-docs`, `tiled-docs`.

**Open question for Phase 2**: the cron `tools/` directories currently live in two places — inside the GitHub skill repo (as `tools/`) AND deployed as siblings at `dev/tools/<name>-docs/`. Should the new layout keep `tools/` inside the skill repo (current pattern), or move them out into deploy-opencode? Recommendation: keep them in the skill repo — they're skill-specific data-sync logic, not central infrastructure.

## agents/ symlinks in worktree's `opencode/agents/`

All point at `../skills/<name>`:
- `ask-ami`, `ask-lcls2`, `ask-s3df`, `ask-slurm-s3df`, `ask-smalldata`, `askcode`, `cuda-docs`, `docs-search`, `experimental-hutch-python`, `find-rings`, `lcls-catalog`, `nano-isaac`

**Missing symlinks (need adding at deploy time)**: `ask-olcf`, `ask-epics`, `ask-nersc`, `ask-tiled`, `ask-slac-ai-tools`, `xpm-seq`. The deployed `opencode/agents/` may have these — needs verification before any cleanup.

## Key observations affecting Phase 2 design

1. **deployed copy is source of truth**, not the worktree's in-tree skills/. Phase 2 deploy.sh must rsync **from** the new skill repos **to** the deployed paths, replacing the current state. No round-tripping through `deploy-opencode/claude/skills/`.

2. **Existing remotes are flat, not `claude/+opencode/`**. Every existing remote needs restructuring (move SKILL.md → `claude/skills/<name>/SKILL.md` and duplicate to `opencode/skills/<name>/SKILL.md`; same for any scripts/bin/env.sh/setup.sh/references/tools). That makes Phase 5 ralph stories non-trivial — not just "add layout" but "reshape existing tree."

3. **`claude/` vs `opencode/` content split — confirmed identical.** Spot-checked: deployed `cuda-docs/SKILL.md` matches worktree's `claude/skills/cuda-docs/SKILL.md`; worktree's `claude/skills/ask-ami/SKILL.md` matches `opencode/skills/ask-ami/SKILL.md`. So the "full duplication" plan reflects existing practice — same content, two locations.

4. **`setup.sh` / `env.sh` are runtime helpers users source.** They likely contain paths to the deployed location. The deploy.sh meta-script needs to ensure these end up correctly installed (or rewritten) for the deployed path.

5. **ask-olcf cron mismatch**: `tools/olcf-docs/` exists at `dev/tools/` but no crontab entry. Either (a) the cron was intentionally disabled, (b) it's scheduled elsewhere, or (c) it was never enabled. Worth asking before encoding "weekly" into the manifest.

6. **`skill-inventory.md` is stale** in 4 places. Should be regenerated from this audit at end of Phase 6.

## Recommended Phase 2 adjustments

- **Manifest field for cron**: store schedule + cron script path, not a boolean. Auto-generate crontab entries from manifest at deploy time (or document them).
- **deploy.sh source choice**: pull from GitHub releases or branches (`ref:` field in manifest) rather than from a working clone. Keeps deploy reproducible.
- **Per-skill SKILL.md comparison**: do a 1-line diff per skill (deployed claude/SKILL.md vs deployed opencode/SKILL.md) before Phase 3 so we know whether duplication is genuine. Cheap to do.

## Recommended Phase 3 (reference skill) choice — confirmed

**cuda-docs** remains the right reference: smallest deployed content (just SKILL.md), no cron, no env.sh, no setup.sh, no scripts. Will not stress-test cron-related parts of deploy.sh — that's good for a first pass, but means Phase 5 ralph stories that involve cron (epics/nersc/s3df/tiled) need a **second reference** added to the guidance doc after the first cron-bearing skill is extracted.
