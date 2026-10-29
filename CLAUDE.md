# OpenCode Centralized Deployment

This project manages the shared opencode deployment for the LCLS team.

## Deployed Directory Structure

All shared files live under `/sdf/group/lcls/ds/dm/apps/`:

| Path | Owner | Purpose |
|------|-------|---------|
| `etc/key.dat` | IT | IT-managed API key (group ps-data); **not** used by the current `opencode.json` |
| `dev/env/key.dat`, `dev/env/slac-key.dat` | You | opencode API keys referenced by `opencode.json` (group ps-users, `0640`); other `dev/env/*.dat` secrets stay owner-only `0600` |
| `dev/bin/uv` | You | Shared uv binary (0.9.8; for skills, lcls-catalog, tree-sitter-db, etc.). `claude-lcls` puts `dev/bin/` FIRST on PATH, so it is the `uv` every claude-lcls session runs |
| `dev/bin/uvx` | You | uvx from the same uv 0.9.8 release; it runs the `uv` beside it, so it always uses the shared uv |
| `dev/bin/docs-index` | You | Shared docs-index script (FTS5 indexer for doc collections) |
| `dev/bin/gh` | You | Symlink to `../gh/current/bin/gh`: the shared GitHub CLI, on `PATH` in claude-lcls agent shells and inside opencode-sandbox. Used by the gh-skills skill. Each user logs in once with this absolute path |
| `dev/gh/<ver>/`, `dev/gh/current` | You | gh releases installed by `tools/gh/install-gh.sh` (sha256 + GitHub build attestation checked, `PROVENANCE` per version). Upgrade or roll back with `--activate <ver>` |
| `dev/bin/hunk` | You | Symlink to `../hunk/bin/hunk`, a wrapper (source `tools/hunk/hunk-wrapper.sh`) that runs `dev/hunk/current/bin/hunk` with a per-user session port (`21000 + uid % 10000`), no update check, and `hunk update` refused. On `PATH` in claude-lcls agent shells and inside opencode-sandbox; users open the viewer with this absolute path. Used by the hunk-review skill |
| `dev/hunk/<ver>/`, `dev/hunk/current`, `dev/hunk/bin/hunk` | You | hunk releases installed by `tools/hunk/install-hunk.sh` (sha256 + GitHub build attestation checked, `PROVENANCE` per version; `skills/` sits beside `bin/` because the binary finds its bundled skills by walking up). Upgrade or roll back with `--activate <ver>`, which also refreshes the wrapper. Bump the hunk-review manifest ref to the same tag |
| `dev/opencode-cli/<ver>/`, `dev/opencode-cli/current` | You | opencode releases installed by `tools/opencode/install-opencode.sh` (sha256 against the release's asset digest + GitHub release attestation, `PROVENANCE` per version). `opencode-sandbox` runs `current/bin/opencode`; installing does not move `current`, `--activate <ver>` does (upgrade or rollback). No `dev/bin` link. See "Shared opencode binary" under Key Config Details |
| `dev/python/` | You | Shared uv-managed Python installs (3.14, 3.11, 3.9); venvs symlink here instead of per-user `~/.local/share/uv/python/`. Writable by you only (ACL `group::r-x`) |
| `dev/opencode/opencode.json` | You | Shared config (provider, models) |
| `dev/opencode/agents/*.md` | You | Agent definitions |
| `dev/opencode/commands/*.md` | You | Slash commands (approval, clarify, taskify) |
| `dev/opencode/v2/opencode.jsonc` | You | opencode **2.x-only** settings (1-hour cache, effort-update compatibility). opencode-sandbox links it into each user's 2.x config folder; 1.x never reads `v2/` (hand-installed, mirrors `opencode/v2/`) |
| `dev/opencode/plugin/cache-ttl.js` | You | opencode plugin: 1-hour prompt cache for Claude main sessions, Haiku excluded (hand-installed, mirrors `opencode/plugin/`) |
| `dev/opencode/skills/lcls-catalog/` | You | lcls-catalog skill |
| `dev/opencode/skills/askcode/` | You | askcode skill (code indexing) |
| `dev/opencode/skills/ask-lcls2/` | You | ask-lcls2 skill (lcls2/psana2 codebase) |
| `dev/opencode/skills/ask-smalldata/` | You | ask-smalldata skill (smalldata_tools codebase) |
| `dev/opencode/skills/cuda-docs/` | You | cuda-docs skill (CUDA documentation search) |
| `dev/opencode/skills/ask-slurm-s3df/` | You | ask-slurm-s3df skill (S3DF Slurm cluster assistant) |
| `dev/opencode/skills/nano-isaac/` | You | nano-isaac skill (AI catalysis research assistant for AP-XPS) |
| `dev/opencode/skills/docs-search/` | You | docs-search skill (documentation search strategy using docs-index) |
| `dev/opencode/skills/ask-s3df/` | You | ask-s3df skill (S3DF documentation assistant) |
| `dev/opencode/skills/find-rings/` | You | find-rings skill (diffraction ring detection for detector calibration) |
| `dev/opencode/skills/experimental-hutch-python/` | You | experimental-hutch-python skill [EXPERIMENTAL] (beamline control assistant + IPython bridge) |
| `dev/opencode/skills/ask-olcf/` | You | ask-olcf skill (OLCF documentation assistant) |
| `dev/opencode/skills/ask-epics/` | You | ask-epics skill (EPICS documentation assistant) |
| `dev/opencode/skills/ask-slac-ai-tools/` | You | ask-slac-ai-tools skill (which AI tools are approved at SLAC, including PHI/CUI eligibility) |
| `dev/opencode/skills/confluence-search/` | You | confluence-search skill (live CQL search of SLAC Confluence; **per-user token**, no shared credential) |
| `dev/opencode/skills/elog-search/` | You | elog-search skill (live read-only search of the LCLS eLog; **per-user S3DF token**, no shared credential) |
| `dev/opencode/skills/jira-search/` | You | jira-search skill (live JQL search of SLAC Jira, read-only; **per-user token**, no shared credential) |
| `dev/opencode/skills/gh-skills/` | You | gh-skills skill (GitHub CLI power-user guide; runs the shared `dev/bin/gh` with the user's own `gh` login). Also in `dev/claude/skills/` |
| `dev/opencode/skills/hunk-review/` | You | hunk-review skill (drives a Hunk viewer the user opens in their own terminal; runs the shared `dev/bin/hunk`). Also in `dev/claude/skills/`. opencode-sandbox binds `$XDG_RUNTIME_DIR/hunk-mcp` read-only so the keys reach it |
| `dev/claude/skills/make-goal/` | You | make-goal skill (writes contracts for Claude Code's `/goal` loop). **Claude-only** (`harness.targets: ["claude"]`): opencode has no `/goal`, so there is no opencode copy |
| `dev/data/sdf-docs/` | You | sdf-docs git repo with FTS5 search index (from slaclab/sdf-docs, branch: prod) |
| `dev/tools/sdf-docs/` | You | sdf-docs sync scripts (daily git pull + re-index) |
| `dev/data/olcf-docs/` | You | olcf-user-docs git repo with FTS5 search index (from olcf/olcf-user-docs) |
| `dev/tools/olcf-docs/` | You | olcf-docs sync scripts (weekly git pull + re-index) |
| `dev/data/epics-docs/` | You | 26 epics-base GitHub repos with FTS5 search index |
| `dev/tools/epics-docs/` | You | epics-docs sync scripts (weekly git pull + re-index) |
| `dev/data/cuda-docs/` | You | CUDA documentation markdown files (Best Practices, Runtime API, Driver API) |
| `dev/data/nano-isaac/` | You | nanoISAAC data files (JSON databases, Python scripts, experimental data) |
| `dev/data/ask-slac-ai-tools/ai-tooling.db` | You | SLAC AI tools SQLite DB (FTS5; ~53 tools, 5 data classifications, 12 policy resources) |
| `dev/software/lcls2/` | You | lcls2 git repo with .agent_docs and .code-index.db |
| `dev/software/smalldata_tools/` | You | smalldata_tools git repo with .agent_docs and .code-index.db |
| `dev/data/confluence-doc/lcls-docs.db` | You | Confluence docs SQLite DB |
| `dev/data/daq-logs/daq_logs.db` | You | DAQ error logs SQLite DB |
| `dev/data/lcls-catalog/lcls_parquet/` | You | Catalog parquet files |
| `dev/data/elog-copilot/elog-copilot.db` | You | Elog experiment SQLite DB (~1.3G, symlink to latest) |
| `dev/data/smartsheet/closeout_notes.db` | You | Smartsheet experiment closeout SQLite DB |
| `dev/tools/confluence-doc/` | You | Confluence export pipeline (git repo) |
| `dev/tools/lcls-catalog/` | You | lcls-catalog uv project |
| `dev/tools/daq-logs/` | You | DAQ log sync scripts (git clone) |
| `dev/tools/elog-copilot/` | You | elogfetch uv project (**pinned at v1.0.0-stable, detached HEAD — do NOT git pull**) |
| `dev/tools/smartsheet/` | You | Smartsheet closeout sync scripts (git clone) |
| `dev/tools/nano-isaac/` | You | nano-isaac uv project (DTCS runtime for XPS simulations) |
| `dev/tools/find-rings/` | You | find-rings uv project (numpy + Pillow for ring detection) |
| `dev/tools/tree-sitter-db/` | You | Code indexing tool (uv project) |

Employees set `OPENCODE_CONFIG_DIR=/sdf/group/lcls/ds/dm/apps/dev/opencode` to use this.

## Source → Deploy Mapping

Deployed files are copies (not symlinks) from these source projects:

| Deployed file | Source |
|---------------|--------|
| `agents/elog-copilot.md` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-skills/.opencode/agents/elog-copilot.md` |
| `agents/daq-logs.md` | `/sdf/data/lcls/ds/prj/prjcwang31/results/proj-debug-daq/.opencode/agents/daq-logs.md` |
| `agents/confluence-doc.md` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/.opencode/agents/confluence-doc.md` |
| `skills/lcls-catalog/` | `/sdf/scratch/users/c/cwang31/proj-lcls-catalog/.opencode/skills/lcls-catalog/` |
| `data/confluence-doc/lcls-docs.db` | Cron job via `tools/confluence-doc/scripts/confluence-cron.sh` (daily at midnight on sdfcron001) |
| `tools/confluence-doc/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/` (minimal file set, git repo) |
| `data/daq-logs/daq_logs.db` | Cron job via `tools/daq-logs/scripts/run_daq_log_sync.sh` (every 5 min on sdfcron001) |
| `tools/daq-logs/` | `git@github.com:carbonscott/lcls-daq-browser-indexing-scripts.git` |
| `data/lcls-catalog/lcls_parquet/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/lcls_parquet/` |
| `tools/lcls-catalog/` | `/sdf/scratch/users/c/cwang31/proj-lcls-catalog/` |
| `tools/elog-copilot/` | `/sdf/data/lcls/ds/prj/prjcwang31/results/fetch-elog/` |
| `data/elog-copilot/elog-copilot.db` | Generated by elogfetch cron job (every 6h on sdfcron001) |
| `agents/smartsheet.md` | Authored directly in deployed copy |
| `tools/smartsheet/` | `git@github.com:carbonscott/smartsheet-db-scripts.git` |
| `data/smartsheet/closeout_notes.db` | Cron job via `tools/smartsheet/scripts/smartsheet-cron.sh` (daily on sdfcron001) |
| `skills/askcode/` | Authored directly in deployed copy |
| `tools/tree-sitter-db/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/fun/play-tree-sitter/tree-sitter-db/` |
| `software/lcls2/` | `git@github.com:slac-lcls/lcls2.git` (full clone) |
| `software/lcls2/.agent_docs/` | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/lcls2/.agent_docs/` |
| `software/lcls2/.code-index.db` | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/lcls2/.code-index.db` |
| `software/smalldata_tools/` | `git@github.com:slac-lcls/smalldata_tools.git` (full clone) |
| `software/smalldata_tools/.agent_docs/` | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/smalldata_tools/.agent_docs/` |
| `software/smalldata_tools/.code-index.db` | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/smalldata_tools/.code-index.db` |
| `skills/ask-lcls2/` | Authored directly in deployed copy |
| `skills/ask-smalldata/` | Authored directly in deployed copy |
| `skills/cuda-docs/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/cuda-docs/` |
| `data/cuda-docs/*.md` | Static markdown files (no cron job needed) |
| `skills/ask-slurm-s3df/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-slurm-s3df/` |
| `skills/docs-search/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/docs-search/` |
| `bin/docs-index` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/docs-search/scripts/docs-index` |
| `skills/ask-s3df/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-s3df/` |
| `data/sdf-docs/` | `https://github.com/slaclab/sdf-docs.git` (branch: prod); cron via `tools/sdf-docs/scripts/sdf-docs-cron.sh` (daily) |
| `tools/sdf-docs/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-s3df/tools/` |
| `commands/*.md` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/opencode/commands/` |
| `skills/nano-isaac/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/nano-isaac/` (skill + sub-skills + references) |
| `data/nano-isaac/` | nanoISAAC repo data files (copied by `deploy-nano-isaac.sh`) |
| `tools/nano-isaac/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/nano-isaac/tool/` (env.sh + pyproject.toml) |
| `skills/find-rings/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/find-rings/` (skill + references + scripts) |
| `tools/find-rings/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/find-rings/tool/` (env.sh + pyproject.toml) |
| `skills/experimental-hutch-python/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/experimental-hutch-python/` (skill + references + scripts) |
| `skills/ask-olcf/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-olcf/` |
| `data/olcf-docs/` | `https://github.com/olcf/olcf-user-docs.git`; cron via `tools/olcf-docs/scripts/olcf-docs-cron.sh` (weekly) |
| `tools/olcf-docs/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-olcf/tools/` |
| `skills/ask-epics/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-epics/` |
| `data/epics-docs/` | `https://github.com/epics-base/*.git` (26 repos); cron via `tools/epics-docs/scripts/epics-docs-cron.sh` (weekly) |
| `tools/epics-docs/` | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-epics/tools/` |
| `skills/ask-slac-ai-tools/` | `git@github.com:carbonscott/ask-slac-ai-tools.git` cloned to `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-slac-ai-tools/` |
| `data/ask-slac-ai-tools/ai-tooling.db` | Built via `setup.sh` in source clone, then `cp build/ai-tooling.db /sdf/group/lcls/ds/dm/apps/dev/data/ask-slac-ai-tools/` (no cron — static curated data) |
| `skills/confluence-search/` | `git@github.com:carbonscott/slac-confluence-search.git` via `skills.manifest.json` + `./deploy.sh` (no data dir — the skill queries Confluence live) |
| `skills/elog-search/` | `git@github.com:carbonscott/slac-elog-search.git` via `skills.manifest.json` + `./deploy.sh` (no data dir — the skill queries the eLog live) |
| `skills/jira-search/` | `git@github.com:carbonscott/slac-jira-search.git` via `skills.manifest.json` + `./deploy.sh` (no data dir — the skill queries Jira live) |
| `skills/gh-skills/` (both trees) | `git@github.com:carbonscott/gh-skills.git` via `skills.manifest.json` + `./deploy.sh` (`harness.source: "."`, SKILL.md at the repo root) |
| `claude/skills/make-goal/` (claude tree only) | `git@github.com:carbonscott/make-goal.git` via `skills.manifest.json` + `./deploy.sh` (`harness.source: "."`, `harness.targets: ["claude"]`) |
| `bin/gh`, `gh/<ver>/` | GitHub release `cli/cli` v<ver>, via `tools/gh/install-gh.sh <ver>` |
| `skills/hunk-review/` (both trees) | `git@github.com:modem-dev/hunk.git` via `skills.manifest.json` + `./deploy.sh` (`harness.source: "packages/hunk/skills/hunk-review"`, ref = the commit of the installed release's tag) |
| `bin/hunk`, `hunk/<ver>/`, `hunk/bin/hunk` | GitHub release `modem-dev/hunk` v<ver> (`hunkdiff-linux-x64.tar.gz`), via `tools/hunk/install-hunk.sh <ver>` |
| `opencode/v2/opencode.jsonc` | `opencode/v2/opencode.jsonc` in this repo, copied by hand (like `opencode.json`) |
| `opencode-cli/<ver>/`, `opencode-cli/current` | GitHub release `anomalyco/opencode` v<ver> (`opencode-linux-x64.tar.gz`), via `tools/opencode/install-opencode.sh <ver>` then `--activate <ver>` |

When copying agents/skills, hardcoded paths must be updated to the shared locations.

## Updating Deployed Data

```bash
# Confluence docs DB — managed by cron (daily at midnight via tools/confluence-doc/scripts/confluence-cron.sh)
# No manual copy needed. To check status:
#   /sdf/group/lcls/ds/dm/apps/dev/tools/confluence-doc/scripts/confluence-cron.sh status

# DAQ logs DB — managed by cron (every 5 min via tools/daq-logs/scripts/sync-cron.sh)
# No manual copy needed. To check status:
#   /sdf/group/lcls/ds/dm/apps/dev/tools/daq-logs/scripts/sync-cron.sh status

# Parquet catalog data (5.9G)
rsync -a --exclude='.uv-cache' \
   /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/lcls_parquet/ \
   /sdf/group/lcls/ds/dm/apps/dev/data/lcls-catalog/lcls_parquet/

# Smartsheet closeout DB — managed by cron (daily via tools/smartsheet/scripts/smartsheet-cron.sh)
# No manual copy needed. To check status:
#   tail /sdf/group/lcls/ds/dm/apps/dev/data/smartsheet/cron.log

# sdf-docs — managed by cron (daily via tools/sdf-docs/scripts/sdf-docs-cron.sh)
# No manual copy needed. To check status:
#   tail /sdf/group/lcls/ds/dm/apps/dev/data/sdf-docs/cron.log

# olcf-docs — managed by cron (weekly via tools/olcf-docs/scripts/olcf-docs-cron.sh)
# No manual copy needed. To check status:
#   tail /sdf/group/lcls/ds/dm/apps/dev/data/olcf-docs/cron.log

# epics-docs — managed by cron (weekly via tools/epics-docs/scripts/epics-docs-cron.sh)
# No manual copy needed. To check status:
#   tail /sdf/group/lcls/ds/dm/apps/dev/data/epics-docs/cron.log

# ask-slac-ai-tools — static curated data (no cron). To refresh:
#   cd /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-slac-ai-tools
#   git pull && UV_PYTHON_INSTALL_DIR=/sdf/group/lcls/ds/dm/apps/dev/python ./setup.sh
#   cp build/ai-tooling.db /sdf/group/lcls/ds/dm/apps/dev/data/ask-slac-ai-tools/ai-tooling.db

# confluence-search — no data to sync (live API). Manifest-driven like the other
# externalized skills; to ship a new version, push upstream then:
#   ./deploy.sh confluence-search

# elog-search — no data to sync (live API), same as confluence-search:
#   ./deploy.sh elog-search

# jira-search — no data to sync (live API), same as confluence-search:
#   ./deploy.sh jira-search
```

## Key Config Details

- `opencode.json` references two API keys: `{file:/sdf/group/lcls/ds/dm/apps/dev/env/key.dat}` (Anthropic) and `{file:/sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat}` (SLAC gateway). Both are group `ps-users`, `0640`; re-assert with `tools/fix-key-perms.sh`. The IT-managed `etc/key.dat` is **not** used by the current config.
- `opencode.json` model conventions (JSON has no comments, so they live here). **Claude 5 entries steer reasoning with `effort`, not `thinking.budgetTokens`**: opencode's bundled `@ai-sdk/anthropic` sends it as `output_config.effort` plus the `effort-2025-11-24` beta, and the gateway honours it -- measured 2026-09-19, same prompt gave 256 output tokens at `effort=low` and 1404 at `effort=max`. The pre-Claude-5 entries keep `thinking.budgetTokens`; mixed styles are fine because each model resolves its own `variants` key, so "medium" means medium effort on Sonnet 5 and an 8000-token thinking budget on Sonnet 4.6.
- **Never append `[1m]` to a model id in `opencode.json`.** Claude Code strips that suffix; opencode does not, and the gateway answers `slac/us.anthropic.claude-opus-5[1m]` with `400 Invalid model name passed in model=...`. The plain id already advertises 1M input / 128k output, recorded in each model's `limit` block. `claude/settings.template.json` *does* need the suffix -- see `docs/claude-code-lcls-setup.md` -- so do not copy ids between the two files.
- **GPT models live in a separate `slac-openai` provider** (same gateway URL and `slac-key.dat`, but `@ai-sdk/openai`, i.e. the OpenAI Responses API), because the `slac` provider speaks the Anthropic protocol. Added 2026-10-15: `us.openai.gpt-6-sol` (GPT-6 Sol, Bedrock Converse) and `openai.gpt-5.6-sol` (GPT-5.6 Sol, Bedrock Mantle). The gateway is LiteLLM; `GET /v1/model/info` with the shared key shows each model's Bedrock backend and price. LiteLLM's prices are ~1.1x the list prices recorded in `cost`, the same ratio as the Claude entries. These entries define no `variants`: opencode 1.2.10 generates `low`/`medium`/`high` (`reasoningEffort`) for any `@ai-sdk/openai` model with `reasoning: true`, and the gateway honours them (GPT-6 Sol, same prompt: 318 reasoning tokens at low, 1034 at high). opencode's built-in GPT defaults key on the substring `gpt-5`, so GPT-5.6 Sol also gets `textVerbosity: low` (terser replies) and GPT-6 Sol does not. opencode always sends `store: false` to `@ai-sdk/openai`; the model-level `include: ["reasoning.encrypted_content"]` keeps prior reasoning sendable when no variant is active. It is defensive -- a multi-tool-call run on GPT-6 Sol with no variant and no `include` also passed. Both Responses and chat completions (`@ai-sdk/openai-compatible`) passed in the sandbox; Responses was chosen because the chat path reports no reasoning tokens for GPT-6 Sol.
- `model` is the default for new sessions (`slac/us.anthropic.claude-opus-5-5` since 2026-10-15, previously `slac/us.anthropic.claude-sonnet-5`). It runs at medium effort because **each model's `options` repeat its `medium` variant** (`effort: medium` on the Claude 5 models, an 8000-token `thinking` budget on Sonnet/Opus 4.6, `reasoningEffort: medium` + `reasoningSummary: auto` on both GPT models -- the same values opencode generates for their `medium` variant). Model `options` go into every request for that model, main sessions and subagents alike, and a variant the user picks (ctrl-t, `--variant high`) is merged over them, so it still wins. The `agent.*.variant: "medium"` entries are no longer what does it: opencode 1.19.x applies an agent's `variant` only when that agent also sets its own `model` (`createUserMessage` in `session/prompt.ts`), and ours do not, so on 1.19.5 the default Opus 5.5 call carried no effort at all (the API default is high) until the model options were added (2026-10-29). 1.2.10 applied the agent variant, and with the options it sends the same `effort: medium` as before (checked on both versions with a `chat.params` probe plugin). The agent entries stay because 1.2.10's TUI labels the variant from them. Haiku has no `options` on purpose: it is `small_model`, and 1.19.x already gives small-model calls (session titles) the model's FIRST variant, which for Haiku is the 4000-token thinking budget. It applies to `opencode-sandbox` and to the `opencode()` wrapper in `docs/setup.md`, since both read this file; `small_model` is what runs session titles and other background work (`slac/us.anthropic.claude-haiku-4-5-20251001-v1:0`). Leaving `small_model` unset sends background work to the default model.
- `opencode.json` is hand-maintained: **`deploy.sh` never writes it.** Take a dated `.bak` before editing, and mirror any change into the repo's `opencode/opencode.json`, which drifted a full generation behind the live file before 2026-09-19.
- **`dev/opencode/plugin/cache-ttl.js` gives Claude models a 1-hour prompt cache.** opencode has no TTL setting: its `applyCaching` hard-codes `cache_control {type:"ephemeral"}` (5 minutes) in 1.2.10 and still in upstream 1.19.1 (request anomalyco/opencode#51109 is open). The gateway honours `ttl: "1h"` with no beta header, so the plugin's `config` hook wraps the `slac` provider's `fetch` and stamps the ttl onto unstamped markers. It applies to main sessions of every `slac` model whose id starts with `us.anthropic.claude-`, except Haiku; subagents stay on 5 minutes, which matches Claude Code's `promptCacheTtl`. Haiku is excluded because it is `small_model`: its one-off title and summary requests run inside main sessions and would pay the 1-hour write price for nothing. All seven `slac` Claude ids (Sonnet 4.6, Opus 4.6, Haiku 4.5, Sonnet 5, Opus 5, Opus 5.5, Fable 5.1) landed in `ephemeral_1h` on a raw `ttl: "1h"` request on 2026-10-15. A future model the gateway gives no 1h cache falls back to 5 minutes without an error. Opus 5.5 only from PR #44; widened in the PR after it. Measured 2026-10-15 with a 6.7-minute bash sleep between two requests in one process: stock opencode read 0 and rewrote 31.9k tokens; with the plugin it read all 31.8k back. opencode loads `{plugin,plugins}/*.{ts,js}` from `OPENCODE_CONFIG_DIR` automatically, so there is no `opencode.json` entry. Like `opencode.json`, it is hand-installed (`deploy.sh` never touches `dev/opencode/plugin/`): mirror `opencode/plugin/cache-ttl.js` and keep the two byte-identical. Upgrades: it relies on the plugin `config` hook, the provider honouring a custom `options.fetch`, and the plugin `client.session.get`. Re-verified unchanged from the deploy layout on 1.18.18 and upstream 1.19.1 (2026-10-15), and those hooks are still there in the 1.19.1 source. Every failure path falls back to the request as opencode built it, so a future break would mean a silent return to 5 minutes rather than an opencode error. After any opencode bump, run one Opus prompt with `OPENCODE_CACHE_TTL_LOG` set and check for `"ttl":"1h"` and a non-zero `ephemeral_1h_input_tokens`. Per-user switches: `OPENCODE_CACHE_TTL=off` disables it, and `OPENCODE_CACHE_TTL_LOG=<file>` logs each request's cache usage (inside the sandbox, prefix the variable with `APPTAINERENV_`). Team-wide rollback: rename the file to `cache-ttl.js.disabled`; new opencode processes pick that up. Cost: a 1-hour write costs 2x the input price against 1.25x for 5 minutes, on every model (Sonnet 5 on the gateway: $6.60 against $4.125/MTok; Opus 5.5: $8.80 against $5.50). Each avoided cold resume saves about 1.15x input per token. `cost.cache_write` stays at the 5-minute price, so opencode's cost display under-reports 1-hour writes. Separately, the cache never survives an opencode restart at any TTL: 1.2.10 orders the skill and agent lists in the `skill`/`task` tool descriptions differently on each start, and tools come first in the cached prefix. The hour therefore helps only while the process stays up.
- **Shared opencode binary: `dev/opencode-cli`.** Since 2026-10-29 `opencode-sandbox` runs `dev/opencode-cli/current/bin/opencode` (1.19.5), installed by `tools/opencode/install-opencode.sh`. Before that it ran psdatmgr's 1.2.10 at `dev/code/.opencode/bin`, which nobody on the team can update (the directory ACL names cwang31 `rwx`, but its mask is `r-x`). Upstream (`anomalyco/opencode`) ships two lines: OpenCode 1 (`v1.19.x`, still patched) and OpenCode 2 (`v2.x`, published as `@opencode/cli` since v2.0.0 on 2026-09-11; GitHub has Releases only from 2.2.0, 2026-10-27). 1.x stays `current`; 2.x is opt-in, see the next bullet. Verification: releases carry no `SHA256SUMS`, and `gh attestation verify` 404s because there is no build provenance. The installer checks the archive against the sha256 digest GitHub's release API reports, then runs `gh release verify-asset`, which checks GitHub's signed release attestation (it lists every asset's digest and rejects a modified file). 1.2.10 predates release attestations and is installed with `OPENCODE_ATTEST=skip` plus a note.
  **Upgrade:** (1) `tools/opencode/install-opencode.sh <ver>`, which does not move `current`. (2) Try it with `OPENCODE_SANDBOX_VERSION=<ver> opencode-sandbox --incognito -- ...`, always `--incognito`, because a new version adds tables to the session database. Compare `debug skill`, `agent list` and `models` against the current version. Run the default model with a subagent. Do the `OPENCODE_CACHE_TTL_LOG` check from the bullet above. Load `tools/opencode/effort-probe.js` (instructions in its header) and confirm the default model logs `effort: medium`. Drive the TUI once (e.g. in tmux). (3) `tools/opencode/install-opencode.sh --activate <ver>`. New launches get it; running sessions keep their version. **Rollback:** `--activate <old>` for everyone, or `OPENCODE_SANDBOX_VERSION=<old>` for one person. A session database touched by 1.19.5 still opened in 1.2.10 (tested 2026-10-29).
  **Behaviour that changed between 1.2.10 and 1.19.x:** an agent's `variant` applies only when the agent also sets `model` (see the `model` bullet; fixed with model `options`). Small-model calls (titles) get the small model's first variant, so Haiku titles now run with a 4000-token thinking budget. The legacy `tui` key in `opencode.json` is ignored rather than migrated, so the shared file is never rewritten. There is a new built-in `customize-opencode` skill. The TUI shows "/update to upgrade to OpenCode 2.0" unless `OPENCODE_DISABLE_AUTOUPDATE=1`, which the launcher sets. Unchanged in both versions: the absolute-path `edit: deny` rules in `opencode.json` never match. The `edit` permission is checked against a project-relative path (logged as `tmp/permtest.txt` for `/tmp/permtest.txt`), so a write to `/tmp` inside the sandbox succeeds. The read-only binds are what protect `dev/` and `/sdf/data/lcls`.
- **opencode 2.x is opt-in: `OPENCODE_SANDBOX_VERSION=2.2.1 opencode-sandbox`** (since 2026-10-29; 1.19.5 stays `current`). Upstream's guide is `services/www/src/docs/content/migrate-v1.mdx` (opencode.ai/v2/docs/migrate-v1). What 2.x changes, and what the launcher does about it (all measured inside the sandbox on 2.2.1):
  - **Config folder.** 2.x treats `OPENCODE_CONFIG_DIR` as the user's own config folder and **writes** `service.json` (its local server password) and `cli.json` there, so it cannot use the read-only shared folder. Its server crashed on `service.json.tmp`. For 2.x the launcher builds `$SCRATCH_HOME/.config/opencode-lcls-v2/`: links to the shared `opencode.json`, `agents/`, `commands/` and `skills/`; `opencode.jsonc` linked to `dev/opencode/v2/opencode.jsonc`; and a `service.json`. It does NOT link `plugin/`, because 1.x plugins do not load in 2.x (the TUI would show "1 plugin failed"). `--no-sandbox` refuses 2.x: pointed at the shared folder it fails for users, and for the folder's owner it would leave a password file readable by all of ps-users.
  - **Background server.** By default 2.x starts one detached server per user on the fixed port 127.0.0.1:49374 (upstream #50672), which a second user on a login node cannot bind. `service.json` `{"disabled": true}` makes each session start a private server on a random port that exits with it ("standalone"); no process was left behind. Not every subcommand accepts the `--standalone` flag (`debug paths` rejects it), so the file is the switch.
  - **Session history.** On first start, 2.x copies 1.x sessions into new tables, once. Measured: a turn made in 2.x was invisible to 1.19.5, and a 1.19.5 session made afterwards was invisible to 2.x. So 2.x gets its own database (`OPENCODE_DB=$SCRATCH_HOME/.local/share/opencode/opencode-v2.db`), seeded once with `sqlite3 .backup` from the 1.x one. The 1.x database was unchanged after 2.x work, so going back loses nothing; work done in 2.x stays in 2.x.
  - **`opencode.json` loads unchanged** (same 20 models). 2.x logs warnings for `agent.*.variant` (no `model`) and model `reasoning`, both ignored. Effort on the wire matched 1.19.5: Opus 5.5 `effort: medium` in main and subagent, Sonnet 4.6 thinking 8000, GPT-6 Sol `reasoning.effort: medium`, `model#high` gives high. `dev/opencode/v2/opencode.jsonc` adds two things in native 2.x syntax. (1) `settings.cache.ttl: "1h"` on the `slac` provider replaces `cache-ttl.js`, with Haiku pinned to `5m` for titles. Unlike the plugin it also gives subagents and compaction 1 hour, so a subagent's first write costs ~0.6x more (Opus 5.5 ~13k tokens: about $0.04). (2) `compatibility.supportsEffortUpdates: false` on each Claude 5 model. Without it, a mid-session effort change goes out as a per-message field that has no effect through LiteLLM (upstream #51146). It has to sit on each model: a provider-level value was overridden by the model entries converted from `opencode.json`. Measured: medium, then `#high` gave high, then `#low` gave low, all top-level.
  - **Other 2.x differences users meet:**
    - New TUI and keys (shift+tab agents, `/goal`); TUI settings move to `cli.json`.
    - Only `AGENTS.md` is read; there is no `CLAUDE.md` fallback.
    - Todos are off by default. `external_directory` is allowed by default; the sandbox binds still bound what is reachable.
    - The shell tool is named `shell`. Permission actions: `bash` -> `shell`, `task` -> `subagent`.
    - CLI: `--variant` is gone (use `-m provider/model#variant`); `debug skill` and `agent list` are gone (use `debug agents`); `models` takes no provider and no `--verbose`.
    - The TUI shows a "Getting started" panel that advertises the free `opencode/*` models; `disabled_providers: ["opencode"]` hides them in both versions (not applied, a policy call).
    - Open upstream bugs at 2.2.1 include plan mode (#60250), empty subagent results (#59051) and missing titles (#58176).
  - **Testing 2.x:** use `tools/opencode/effort-probe-v2/` (a directory plugin; 2.x needs directories for configured plugin paths). It logs the outgoing request body itself, so it also shows `cache_control` ttls; `OPENCODE_CACHE_TTL_LOG` does nothing in 2.x. `--version` prints `opencode v2.2.1`, which install-opencode.sh handles.
  - **Before making 2.x `current`:** the `docs/setup.md` `opencode()` wrapper runs `current/bin` against the SHARED config folder, which 2.x writes to, so change it first. `install-opencode.sh --activate` refuses a 2.x version without `OPENCODE_ACTIVATE_V2=1`. Also wait for a 2.2.x that fixes plan mode.
- Config precedence: global user < OPENCODE_CONFIG_DIR < project < OPENCODE_CONFIG_CONTENT
- The `tools/lcls-catalog/env.sh` defines the `lcat` shell function and sets `LCLS_CATALOG_APP_DIR` and `CATALOG_DATA_DIR`
- The `tools/daq-logs/scripts/env.sh` sets `DAQ_LOGS_APP_DIR` and `DAQ_LOGS_DATA_DIR`; cron job runs every 5 min syncing DAQ logs to `data/daq-logs/`
- The `tools/elog-copilot/env.sh` defines `ELOG_COPILOT_APP_DIR` and `ELOG_COPILOT_DATA_DIR`; cron job runs every 6 hours updating `data/elog-copilot/elog-copilot.db`
- The `tools/confluence-doc/env.sh` defines `CONFLUENCE_DOC_APP_DIR` and `CONFLUENCE_DOC_DATA_DIR`; cron job runs daily at midnight exporting Confluence docs to `data/confluence-doc/lcls-docs.db`
- The `tools/smartsheet/env.sh` defines `SMARTSHEET_APP_DIR` and `SMARTSHEET_DATA_DIR`; reads API key from `dev/env/smartsheet.dat`; cron job runs daily syncing closeout data to `data/smartsheet/`
- The `tools/tree-sitter-db/env.sh` defines `TREE_SITTER_DB_APP_DIR` and `TREE_SITTER_DB_DATA_DIR`; provides `tsdb` wrapper for on-demand code indexing (no cron job)
- The `tools/nano-isaac/env.sh` defines `NANO_ISAAC_APP_DIR` and `NANO_ISAAC_DATA_DIR`; provides `nano_isaac_run` wrapper for DTCS runtime (no cron job)
- The `tools/find-rings/env.sh` defines `FIND_RINGS_APP_DIR`; provides `find_rings_run` wrapper for ring detection (no cron job)
- The `tools/sdf-docs/env.sh` defines `SDF_DOCS_APP_DIR` and `SDF_DOCS_DATA_DIR`; cron job runs daily syncing sdf-docs repo and rebuilding FTS5 search index
- The `tools/olcf-docs/env.sh` defines `OLCF_DOCS_APP_DIR` and `OLCF_DOCS_DATA_DIR`; cron job runs weekly syncing olcf-user-docs repo and rebuilding FTS5 search index
- The `tools/epics-docs/env.sh` defines `EPICS_DOCS_APP_DIR` and `EPICS_DOCS_DATA_DIR`; cron job runs weekly syncing 26 epics-base repos and rebuilding FTS5 search index
- **Skills need symlinks in agents/ for @invocation**: Opencode loads from `agents/` directory. Skills in `skills/` need symlinks in `agents/` to be invoked with `@skill-name`. Current symlinks: `agents/askcode -> ../skills/askcode`, `agents/lcls-catalog -> ../skills/lcls-catalog`, `agents/ask-lcls2 -> ../skills/ask-lcls2`, `agents/ask-smalldata -> ../skills/ask-smalldata`, `agents/cuda-docs -> ../skills/cuda-docs`, `agents/ask-slurm-s3df -> ../skills/ask-slurm-s3df`, `agents/nano-isaac -> ../skills/nano-isaac`, `agents/docs-search -> ../skills/docs-search`, `agents/ask-s3df -> ../skills/ask-s3df`, `agents/find-rings -> ../skills/find-rings`, `agents/experimental-hutch-python -> ../skills/experimental-hutch-python`, `agents/ask-olcf -> ../skills/ask-olcf`, `agents/ask-epics -> ../skills/ask-epics`, `agents/ask-slac-ai-tools -> ../skills/ask-slac-ai-tools`, `agents/confluence-search -> ../skills/confluence-search`. Links are **relative**; `deploy.sh` creates them automatically for manifest skills. The symlink's own group/mode is irrelevant — Linux checks the target's permissions, not the link's.
- The `software/update-index.sh` script updates git repos and regenerates code indexes: `./update-index.sh [lcls2|smalldata_tools|all]`

## Group Ownership Policy

The shared deployment serves the whole employee population — **group `ps-users` (~3700)**, not
`ps-data` (~60). Getting this wrong silently locks employees out (see the xppopr key incident and
the earlier `dev/bin` lockout). Rules:

- **Default: `ps-users` + `g+rX`** for everything under `dev/` that employees read or run —
  `opencode/` (skills/agents/commands), `tools/`, `data/`, `software/`, `python/`, `bin/`. All
  deploy/cron scripts chgrp to `ps-users` (`deploy.sh` defaults `GROUP=ps-users`).
- **Only exceptions kept on `ps-data`:** the elog tools — `tools/elog-copilot`,
  `tools/elogfetch-pr-review`, `tools/elog-copilot-pr-2026-0225` — and `data/elog-copilot`.
- **`dev/env` secrets stay locked:** the directory is `ps-data` with a *traverse-only* ACL
  (`group:ps-users:--x` — no list, no default ACL); only the two opencode API keys are group
  `ps-users` `0640`, the other four `*.dat` secrets stay `0600`. Re-assert with
  `tools/fix-key-perms.sh` after rotating or adding a key.
- **Audit for lockouts** (should report only the elog exceptions, plus stray `psdatmgr`-owned
  junk like `code/.lesshst`):
  ```bash
  find /sdf/group/lcls/ds/dm/apps/dev -path '*/env' -prune -o \
    \( ! -perm -o+r ! -group ps-users -printf '%u %p\n' \)
  ```
- `dev/code` is owned by `psdatmgr` (the old shared opencode 1.2.10 install, which we cannot update) — leave it to IT. `opencode-sandbox` stopped using it on 2026-10-29 (it runs `dev/opencode-cli/current`); only `opencode()` wrappers copied from `docs/setup.md` before then still point at it.

## uv for Shared Deployment

The shared tools use `uv` to manage Python projects. Three settings are critical for multi-user access:

1. **`UV_PYTHON_INSTALL_DIR="/sdf/group/lcls/ds/dm/apps/dev/python"`** — Python interpreters must live in a shared location, not `~/.local/share/uv/python/` (which is owner-only). Each env.sh exports this. When adding a new Python version:
   ```bash
   UV_PYTHON_INSTALL_DIR=/sdf/group/lcls/ds/dm/apps/dev/python uv python install 3.XX
   chgrp -R ps-users /sdf/group/lcls/ds/dm/apps/dev/python && chmod -R g+rX /sdf/group/lcls/ds/dm/apps/dev/python
   ```

2. **`UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache-$USER}"`** — `uv` needs write access to its cache. Each user gets their own cache in `/tmp/`. Cron jobs can override via `env.local`.

3. **`uv run --frozen`** — Wrapper functions (`lcat`, `tsdb`) use `--frozen` so `uv run` doesn't try to sync/write to the shared `.venv`. The venv is pre-built by the maintainer; users only read from it.

After creating or updating a venv, fix permissions:
```bash
chgrp -R ps-data .venv && chmod -R g+rX .venv
```

See `docs/incident-permissions-fix-2026-02-12.md` for full context on these requirements.

## Agent/Skill Config Locations

When modifying an agent or skill, update all copies. Changes in the source are for local development; changes in the deployed copy take effect for all employees.

### lcls-catalog

| Copy | Path |
|------|------|
| Deployed (opencode) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/lcls-catalog/SKILL.md` |
| Source (opencode) | `/sdf/scratch/users/c/cwang31/proj-lcls-catalog/.opencode/skills/lcls-catalog/SKILL.md` |
| Source (claude) | `/sdf/scratch/users/c/cwang31/proj-lcls-catalog/.claude/skills/lcls-catalog/SKILL.md` |

### confluence-doc

| Copy | Path |
|------|------|
| Deployed (opencode agent) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/agents/confluence-doc.md` |
| Source (opencode agent) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/.opencode/agents/confluence-doc.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/proj-confluence-llm/.claude/skills/confluence-doc/SKILL.md` |

### elog-copilot

| Copy | Path |
|------|------|
| Deployed (opencode agent) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/agents/elog-copilot.md` |
| Source (opencode agent) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-skills/.opencode/agents/elog-copilot.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/elog-copilot-skills/.claude/skills/elog-copilot/SKILL.md` |

**Deployed tools frozen (2026-02-25):** The deployed `tools/elog-copilot/` directory is pinned at tag `v1.0.0-stable` (commit `4dc1759`) with detached HEAD to prevent accidental `git pull`. The elogfetch repo has 12+ open PRs for a major refactor (async, SQLAlchemy/Alembic, gssapi). Review and merge PRs on GitHub or in the source dir — never git pull in the deployed dir. Upgrade procedure:
1. Disable cron: `tools/elog-copilot/scripts/elog-cron.sh disable`
2. Update code: `cd tools/elog-copilot && git fetch origin && git checkout v<new-tag> --detach`
3. Rebuild venv: `uv sync && chgrp -R ps-data .venv && chmod -R g+rX .venv`
4. Test: `scripts/elog-cron.sh test`
5. Re-enable cron: `scripts/elog-cron.sh enable`

### smartsheet

| Copy | Path |
|------|------|
| Deployed (opencode agent) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/agents/smartsheet.md` |

### askcode

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/askcode/SKILL.md` |
| Source (tool) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/fun/play-tree-sitter/tree-sitter-db/` |

### ask-lcls2

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-lcls2/SKILL.md` |
| Software repo | `/sdf/group/lcls/ds/dm/apps/dev/software/lcls2/` |
| Agent docs | `/sdf/group/lcls/ds/dm/apps/dev/software/lcls2/.agent_docs/` |
| Code index | `/sdf/group/lcls/ds/dm/apps/dev/software/lcls2/.code-index.db` |
| Agent docs source | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/lcls2/.agent_docs/` |

### ask-smalldata

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-smalldata/SKILL.md` |
| Software repo | `/sdf/group/lcls/ds/dm/apps/dev/software/smalldata_tools/` |
| Agent docs | `/sdf/group/lcls/ds/dm/apps/dev/software/smalldata_tools/.agent_docs/` |
| Code index | `/sdf/group/lcls/ds/dm/apps/dev/software/smalldata_tools/.code-index.db` |
| Agent docs source | `/sdf/data/lcls/ds/prj/prjcwang31/results/software/smalldata_tools/.agent_docs/` |

### cuda-docs

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/cuda-docs/SKILL.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/cuda-docs/SKILL.md` |
| Data files | `/sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs/*.md` |

### ask-slurm-s3df

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-slurm-s3df/SKILL.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-slurm-s3df/SKILL.md` |
| Reference doc | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/docs/s3df-slurm-research.md` |

### nano-isaac

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/nano-isaac/SKILL.md` |
| Source (skill + tool + scripts) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/nano-isaac/` |
| Upstream repo | `git@github.com:ISAAC-DOE/nanoISAAC.git` |
| Data files | `/sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/` |
| Tool env | `/sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/` |

### ask-s3df

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-s3df/SKILL.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-s3df/SKILL.md` |
| Data (git clone) | `/sdf/group/lcls/ds/dm/apps/dev/data/sdf-docs/` |
| Cron tools | `/sdf/group/lcls/ds/dm/apps/dev/tools/sdf-docs/` |
| Cron tools source | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-s3df/tools/` |

### ask-olcf

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-olcf/SKILL.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-olcf/SKILL.md` |
| Data (git clone) | `/sdf/group/lcls/ds/dm/apps/dev/data/olcf-docs/` |
| Cron tools | `/sdf/group/lcls/ds/dm/apps/dev/tools/olcf-docs/` |
| Cron tools source | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-olcf/tools/` |

### ask-epics

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-epics/SKILL.md` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-epics/SKILL.md` |
| Data (26 git clones) | `/sdf/group/lcls/ds/dm/apps/dev/data/epics-docs/` |
| Cron tools | `/sdf/group/lcls/ds/dm/apps/dev/tools/epics-docs/` |
| Cron tools source | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-epics/tools/` |

### docs-search

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/docs-search/SKILL.md` |
| Deployed (script) | `/sdf/group/lcls/ds/dm/apps/dev/bin/docs-index` |
| Source (claude skill) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/docs-search/SKILL.md` |
| Source (script) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/docs-search/scripts/docs-index` |

### find-rings

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/find-rings/SKILL.md` |
| Source (skill + tool + scripts) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/find-rings/` |
| Tool env | `/sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/` |

### experimental-hutch-python

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/experimental-hutch-python/SKILL.md` |
| Source (skill + scripts) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/experimental-hutch-python/` |
| Prototype | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/fun-stuff/test-hutch-python/` |

### ask-slac-ai-tools

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-slac-ai-tools/SKILL.md` |
| Source (git clone) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/ask-slac-ai-tools/` |
| Upstream repo | `git@github.com:carbonscott/ask-slac-ai-tools.git` |
| Data (SQLite DB) | `/sdf/group/lcls/ds/dm/apps/dev/data/ask-slac-ai-tools/ai-tooling.db` |

### confluence-search

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/confluence-search/SKILL.md` |
| Upstream repo | `git@github.com:carbonscott/slac-confluence-search.git` (manifest entry; deploy staging clone under `/tmp/skill-deploy-$USER/`) |
| Maintainer clone | `/sdf/data/lcls/ds/prj/prjcwang31/results/confluence-search/` (for local work only — **not** the deploy source) |

**Per-user token, and the sandbox needs help finding it (2026-08-13).** The skill
authenticates with each user's own Confluence personal access token — there is no shared
credential, and results are filtered by that account's wiki permissions. Two things follow:

- **Every user must run `scripts/confluence-login` themselves, on the host** (not inside the
  sandbox, where the write lands in the scratch home and is lost). They mint the token first at
  `https://confluence.slac.stanford.edu/plugins/personalaccesstokens/usertokens.action`.
- **`cqlsearch.py` resolves the token from the passwd database (`pwd.getpwuid().pw_dir`), not
  `$HOME`** — deliberate, so it stays correct under cron/sudo. But that defeats apptainer's
  `--home` override: inside `opencode-sandbox` it looks under `/sdf/home`, which the sandbox does
  not bind, and the skill reports a missing token. `sandbox/bin/opencode-sandbox` therefore copies
  the token into the scratch home at launch (mode `600` — the skill rejects any token file
  readable by group or others) and exports `CONFLUENCE_TOKEN_FILE`, which is checked *before* the
  passwd lookup. Consequences: a token rotated mid-session is stale until restart, and
  `confluence-login --force` run inside the sandbox does not persist.

**Deployed as a real copy, not a symlink.** It was first deployed with the upstream repo's own
`install.sh`, which defaults to symlinking — the link pointed into `prjcwang31/results/`, whose
parent chain is `ps-data`-only, so it was invisible to the ~3700 `ps-users` employees. Upstream
now picks the mode from the destination (symlink under `$HOME`, copy anywhere else), but the
shared tree should be deployed with `./deploy.sh confluence-search`, not `install.sh` — that
installer exists for people running Claude Code on their own machine.

**The repo name breaks the `skill-<name>` convention on purpose.** The manifest's explicit `repo`
field makes the name irrelevant to deployment, so `slac-confluence-search` was left alone rather
than renamed. Layout inside the repo does still have to match: `opencode/skills/<name>/` is the
only path `deploy.sh` reads.

### elog-search

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/elog-search/SKILL.md` |
| Upstream repo | `git@github.com:carbonscott/slac-elog-search.git` (manifest entry; staging clone under `/tmp/skill-deploy-$USER/`) |

Read-only by construction: every HTTP call goes through `_get()`, which refuses any route
outside its `READ_ROUTES` allowlist. There is no shared-account fallback anywhere — results are
filtered by the invoking user's own eLog roles, so two people running the same search legitimately
see different numbers of experiments.

**Credential: the user's own S3DF OAuth2 token, minted with `s3df login`.** Each user runs
`/sdf/sw/s3df-cli/bin/s3df login` once (browser + MFA); the token lands in
`~/.s3df-access-token` with metadata in `~/.s3df-token.json`, and refreshes from the stored
refresh token thereafter. The skill also has a Kerberos path, but upstream keeps it undocumented
and we do not use it — see below.

**Sandbox: the token is bind-mounted, unlike the Confluence one, which is copied.** Both skills
need a credential across the `opencode-sandbox` boundary, but the right mechanism differs:

- `s3df login` refreshes by truncating `~/.s3df-access-token` **in place** (shell `>`), so the
  inode is stable and a read-only bind lets a running sandbox see a renewed token. It also keeps
  a second copy of the refresh token off `/sdf/scratch`.
- `confluence-login --force` unlinks and re-creates with `O_CREAT|O_EXCL` — new inode — so a bind
  would go stale anyway; that one stays a copy.

`sandbox/bin/opencode-sandbox` binds both S3DF files read-only at their real paths and exports
`S3DF_TOKEN_FILE` / `S3DF_TOKEN_META`. Those are the names `s3df-login` itself documents and
elog-search honours, so the container never depends on home resolution.

**Kerberos is deliberately not forwarded into the sandbox.** A TGT is a delegatable bearer
credential, `/usr` is bound so `ssh` exists inside the container, and SLAC accepts GSSAPI —
forwarding one would re-enable exactly the SSH the sandbox advertises as disabled. (It is also
mechanically unreachable today: `$KRB5CCNAME` is stripped by `--containall`, host `/tmp` is masked
by the scratch `/tmp`, and `/run/user` is unbound.) With no ccache present the skill's resolver
falls straight through to the S3DF token, so no `--auth` flag is needed.

**Trap worth knowing:** when no credential is usable the skill tells the user to run `kinit` or
`s3df login`. Inside the sandbox `kinit` will never help — the ticket lands on the host and cannot
cross the boundary. The fix is always `s3df login` **on the host**, then restart the sandbox.

### jira-search

| Copy | Path |
|------|------|
| Deployed (opencode skill) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/jira-search/SKILL.md` |
| Deployed (claude skill) | `/sdf/group/lcls/ds/dm/apps/dev/claude/skills/jira-search/SKILL.md` |
| Upstream repo | `git@github.com:carbonscott/slac-jira-search.git` (manifest entry; staging clone under `/tmp/skill-deploy-$USER/`) |

Live JQL search of `jira.slac.stanford.edu` (Jira Data Center 10.3). Results are filtered by the
invoking user's own project permissions, so two people running the same query legitimately see
different issue counts. `jqlsearch.py whoami` says which identity is in play.

**Read-only-ness lives in the code, not in the token.** A Jira personal access token carries its
owner's *full* permissions — Jira Data Center has no read-only PAT — so unlike elog-search there is
no allowlist to lean on. Instead every request in `scripts/jqlsearch.py` is a plain GET except one:
`Client.search()` POSTs because Jira's JQL endpoint takes its query in a request body. That single
body-bearing call creates, edits, transitions and deletes nothing, and the audit that keeps it that
way is a one-line grep over `scripts/` for a second `Request(..., data=...)`. Do not add one.

**Credential: the user's own Jira PAT**, installed with the sibling `scripts/jira-login`. It lands
in `~/.config/jira-search/token`; `$JIRA_TOKEN` and `$JIRA_TOKEN_FILE` override it, in that order.
No shared default and no shared-account fallback. The reader refuses any token file with group or
other bits set (`mode & 0o077`), because these group trees are setgid and group-writable and an
inherited umask leaks the token quietly.

**Sandbox: the token is copied, like the Confluence one — not bound like the S3DF one.**
`jira-login --force` unlinks and re-creates the file with `O_CREAT|O_EXCL`, so the inode changes
and a read-only bind would go stale on the next rotation. `sandbox/bin/opencode-sandbox` installs
the host token at mode 600 under the scratch home and exports `JIRA_TOKEN_FILE` at the copy; the
skill checks that variable before it consults the passwd database, which is what makes it resolve
at all inside a container that does not bind `/sdf/home`.

### commands (approval, clarify, taskify, clarify-before-research)

| Copy | Path |
|------|------|
| Deployed (opencode commands) | `/sdf/group/lcls/ds/dm/apps/dev/opencode/commands/*.md` |
| Source (opencode commands) | `/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/opencode/commands/*.md` |
| Source (claude commands) | `/sdf/home/c/cwang31/.claude/commands/*.md` (personal Claude Code originals) |
