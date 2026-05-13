# Hand-off: externalize knowledge-wrapper skills (2026-05-13)

## Goal

Move all 15 knowledge-wrapper skills out of `deploy-opencode` into per-skill GitHub repos named `skill-*`. Reduce `deploy-opencode`'s in-tree `claude/skills/` and `opencode/skills/` to a manifest + a meta-deploy script that walks the manifest and populates the shared deployed copy at `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/`.

Why this framing: the user wants `deploy-opencode` to stop being the home of skill content — the repo should orchestrate, not contain. Knowledge wrappers (which mostly point at external docs/data sources) are the easiest piece to externalize first. Data-service agents and LCLS-coupled skills are out of scope.

## Current state

Mid-execution, end of Phase 1 (audit), about to start Phase 2 (write the contract). A worktree exists on the remote with a branch ready to receive changes. The audit (`handoff/skill-audit-2026-05-13.md` on the worktree) is the most authoritative document for what each skill currently looks like; it supersedes the stale `handoff/skill-inventory.md`. No GitHub mutations have happened yet. No code in `deploy-opencode` itself has been changed in the worktree.

Six-phase plan was approved: 0 worktree → 1 audit → 2 contract (guidance doc + manifest schema + deploy.sh skeleton) → 3 reference extraction (cuda-docs) → 4 GitHub renames → 5 ralph loop for remaining 12 → 6 cleanup. Tasks 0 and 1 are done. Tasks 2-6 are pending.

## Decisions (with why)

- **Scope = 15 knowledge wrappers**, not 13. *Why*: audit found `skill-inventory.md` lists 15. User confirmed "all knowledge wrappers" earlier; the 13 number was a miscount.
- **Repo names are `skill-*` on GitHub; local dir names inside `skills/` stay prefix-free** (e.g. repo `skill-ask-epics` → local `skills/ask-epics/`). *Why*: putting `skill-` inside a `skills/` dir is "skill" twice. Repo names need the prefix to disambiguate on GitHub.
- **Each repo has `claude/skills/<name>/` and `opencode/skills/<name>/` with full duplicated content. No `shared/` dir.** *Why*: user explicitly rejected `shared/` after considering it. Audit confirmed claude/opencode SKILL.md files are already identical in current practice — duplication preserves existing pattern.
- **No per-repo install scripts.** *Why*: user's view — "typically you don't need install". Deployment handled by central meta-script instead.
- **Deploy mechanism: meta-script in `deploy-opencode` reads the manifest, clones each skill repo, rsyncs the `opencode/skills/<name>/` directory into the deployed location, applies ps-data group + g+rX.** *Why*: user picked this over per-repo `deploy.sh` and over documented-commands-only. Centralizes the permission-handling logic (the recurring gotcha — see `docs/incident-permissions-fix-2026-02-12.md` referenced in CLAUDE.md).
- **Guidance is a single doc + a machine-readable manifest.** *Why*: user picked this over doc-only or manifest-only.
- **Two prefix-less remotes get renamed**: `carbonscott/ask-slac-ai-tools` → `carbonscott/skill-ask-slac-ai-tools`; `carbonscott/xpm-seq-skills` → `carbonscott/skill-xpm-seq` (target name unconfirmed — see open threads). *Why*: user picked "Rename remotes to `skill-*`".
- **Free-form scripts per repo.** No template, no shared installer library. *Why*: user explicitly picked this over the two alternatives; duplication is acceptable per the user.
- **Centrally-managed skills (data services, lcls-catalog) are untouched in this effort.** *Why*: user said "Let's not touch centrally managed skills yet."
- **Work happens in a worktree at `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode-externalize/`, branch `externalize-knowledge-wrappers`, accessed via a second bridge session named `deploy-opencode-externalize`.** *Why*: user wanted a separate worktree; second session keeps the original `deploy-opencode` bridge pointing at the source repo for cross-referencing.
- **Ralph (via `/ralph-lnb`) handles Phase 5 (extraction of the remaining 12 wrappers), but only after Phase 3 reference extraction is done.** *Why*: ralph subagents have no shared context; they need a written contract (guidance doc, manifest schema) AND a worked example to follow, or the first iteration becomes "design + execute" and produces drift.
- **Reference skill = `cuda-docs`.** *Why*: smallest deployed content (just `SKILL.md`), no cron, no `env.sh`/`setup.sh`/`bin/`, no LCLS coupling. Tests the whole pipeline (repo creation, claude/opencode layout, manifest entry, meta-deploy) with minimal complexity. *Caveat*: doesn't exercise cron paths, so a second reference is needed after the first cron-bearing skill is extracted — flag in the guidance doc.
- **Deployed copy at `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/<name>/` is the source of truth for extraction**, not the worktree's `claude/skills/` or `opencode/skills/`. *Why*: audit found the worktree's in-tree skill directories are stale/partial — many missing `env.sh`/`setup.sh`/`bin/` that the deployed copies have. The 10 existing GitHub remotes are also valid sources, but all use a flat layout — they still need restructuring into `claude/+opencode/`.

## Ruled out (with why)

- **`shared/` directory at repo root** (for content shared between claude/ and opencode/). *Why*: user wanted simpler; duplication is acceptable.
- **Per-repo `install.sh`.** *Why*: user said "typically you don't need install".
- **Shared installer library** (one repo provides install helpers, others source it). *Why*: user picked "pure free-form per repo" — accepts duplication, rejects coupling.
- **Renaming local skill dirs to `skill-<name>/`** (e.g. `skills/skill-ask-epics/`). *Why*: redundant naming since dir is already inside `skills/`.
- **Restarting the bridge session with a parent root-dir to cover both repo and worktree in one session.** *Why*: user picked the two-named-sessions option instead.
- **Generating `tasks.json` before the reference extraction.** *Why*: ralph subagents would have no contract to follow; first iteration would be design + execute, which is the ralph anti-pattern.
- **Standardized install scripts via skeleton template.** *Why*: user picked free-form over both template and shared library.
- **Manifest-only minimal-prose guidance** OR **doc-only without manifest**. *Why*: user picked the combination.

## Load-bearing assumptions

- **Bridge topology**: there are two bridge sessions — `deploy-opencode` (rooted at the source repo, `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/`) and `deploy-opencode-externalize` (rooted at the new worktree). The intern must use `bridge --session deploy-opencode-externalize` for all worktree edits. Source-repo lookups go through the other session. Crontab inspection or any `/sdf/group/lcls/ds/dm/apps/` access works through either via `bridge bash` — paths there are absolute, root-dir doesn't apply.
- **GitHub owner is `carbonscott`** — all existing skill remotes are under that account. New repos go there too unless the user says otherwise.
- **ps-data group + g+rX permissions** are required for any deployed file. This is the recurring permissions gotcha. The meta-deploy script must enforce it. See `docs/incident-permissions-fix-2026-02-12.md` (in deploy-opencode source) for full context.
- **`gh` CLI is authenticated** as `carbonscott` or similar (audit's `gh api` calls succeeded without prompting). Don't assume token scope — for `gh repo create` and `gh repo rename`, confirm permissions before bulk operations.
- **Cron host is `sdfcron001`.** Crontab inspection went through that host. Any new cron entries from the manifest deploy go there.
- **Data dirs stay central, never in skill repos.** Specifically: `dev/data/cuda-docs/*.md`, `dev/data/sdf-docs/`, `dev/data/olcf-docs/`, `dev/data/nersc-docs/`, `dev/data/tiled-docs/`, `dev/data/epics-docs/`, `dev/software/lcls2/`, `dev/software/smalldata_tools/`. Skill repos contain only SKILL.md + scripts + references + bin + env.sh + setup.sh + (optionally) tools/. The skill *operates on* central data; it doesn't *contain* it.
- **Existing remotes are flat layout, not claude/+opencode/.** All 10 of them. Phase 5 stories are "restructure existing repo", not "add layout to existing repo" — non-trivial reshape per skill.

## Open threads

- **ask-olcf cron mystery.** `tools/olcf-docs/` is deployed at `dev/tools/olcf-docs/` but there's no crontab entry on sdfcron001. Inventory claimed weekly. Was the cron intentionally disabled? Was it never enabled? Needs user input before encoding "cron: weekly" in the manifest.
- **Cron `tools/` directories — where do they live?** Currently they exist in two places: inside the GitHub skill repo (e.g. `carbonscott/skill-ask-epics/tools/`) AND deployed at `dev/tools/<name>-docs/`. Should the new layout keep `tools/` inside the skill repo (current pattern), or hoist them out into a central `deploy-opencode/tools/` directory? Recommendation in audit: keep inside skill repo, but not yet user-confirmed.
- **Manifest cron field shape.** Boolean (has-cron y/n) or full schedule + script path? Recommendation in audit: schedule + path so deploy step can regenerate crontab entries.
- **xpm-seq rename target name.** Plan defaults to `skill-xpm-seq`. The existing remote is `xpm-seq-skills` (note: "skills" suffix, not "skill" prefix). Need user confirmation before `gh repo rename`.
- **GitHub repo creation policy.** Public vs private? Who runs `gh repo create` — the maintainer manually, or can the meta-deploy / ralph subagent? Not yet decided. Affects Phase 3 (cuda-docs) and any new repos in Phase 5.
- **docs-search content asymmetry.** Worktree's `claude/skills/docs-search/` has `scripts/` + `facility-env.sh` + `SKILL.md`; deployed copy has only `SKILL.md` + `facility-env.sh` (no `scripts/`). Audit's "deployed is source of truth" rule says drop the worktree's `scripts/`. Worth eyeballing before discarding.

## Pointers

- **`handoff/skill-audit-2026-05-13.md` (on the remote worktree)** — the per-skill audit table. **Read this first.** It supersedes the inventory; encodes the actual source-of-truth-per-skill mapping; flags the 4 cron-row inventory errors.
- **`handoff/skill-inventory.md`** — stale on cron data (4 errors). Trust the audit. Will be regenerated in Phase 6.
- **`BRIDGE.md`** — one-line confirmation that bridge sessions are how this work happens.
- **`tools/start-bridge-deploy-opencode.sh`** — how to restart the source-repo bridge if it dies. There is no equivalent script yet for the `deploy-opencode-externalize` session; recreate manually with `bridge-session start --name deploy-opencode-externalize -- ssh sdfiana025 'uv run ~/bridge-server --root-dir /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode-externalize'`.
- **`CLAUDE.md` (in deploy-opencode)** — deployed-directory structure, source→deploy mapping, permissions conventions, lists per-skill source-of-truth paths (some of which the audit invalidates).
- **`docs/incident-permissions-fix-2026-02-12.md`** — the recurring ps-data permissions gotcha. Read before writing the rsync part of `deploy.sh`.
- **The 6-phase plan** — captured in the `/approval` exchange in the conversation; reproduced in shape under "Current state" above. Use it as the canonical sequence.
- **Task list (in-flight)** — 7 tasks via TaskCreate; #1 (worktree) and #2 (audit) done; #3-#7 pending. The next task to claim is #3 (Phase 2: write guidance doc + manifest schema + deploy.sh skeleton).
