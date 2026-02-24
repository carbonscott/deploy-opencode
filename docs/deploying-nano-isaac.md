# Deploying nanoISAAC as an OpenCode Skill

This documents the experience of deploying nanoISAAC (an AI catalysis research assistant from the ISAAC-DOE/nanoISAAC repo) as a shared OpenCode skill. It serves as a reference for future agent skill deployments.

## Background

nanoISAAC is a Claude Code project that teaches the LLM to use DTCS (Digital Twin for Chemical Sciences) to simulate surface chemistry and predict XPS spectra. It has 8 sub-skills (markdown knowledge files), 2 JSON databases, 2 Python scripts, and depends on DTCS (pip package from git). Total essential payload: ~130 KB.

Upstream repo: `git@github.com:ISAAC-DOE/nanoISAAC.git`

## Three-Location Deployed Layout

The skill spans three directories under `/sdf/group/lcls/ds/dm/apps/dev/`:

| Location | Contents | Why separate |
|----------|----------|-------------|
| `opencode/skills/nano-isaac/` | SKILL.md, sub-skills/, references/, scripts/ | OpenCode reads skills from here |
| `data/nano-isaac/` | JSON databases, Python scripts, experimental data | Data files that may update independently of the skill |
| `tools/nano-isaac/` | env.sh, pyproject.toml, .venv/ | Python runtime (DTCS + deps), follows existing tool pattern |

The agent symlink `opencode/agents/nano-isaac -> ../skills/nano-isaac` enables `@nano-isaac` invocation.

## Source Layout

Everything lives under one directory in the deploy-opencode repo:

```
deploy-opencode/claude/skills/nano-isaac/
├── SKILL.md                    # Main skill (persona + routing)
├── sub-skills/                 # 8 domain knowledge files
│   ├── binding-energies.md
│   ├── catalysis-fundamentals.md
│   ├── crn-generation.md
│   ├── edison-search.md
│   ├── mlip-property-prediction.md
│   ├── reaction-parameters.md
│   ├── spectrum-analysis.md
│   └── vamas-xps.md
├── references/
│   └── xps_interpretation.md
├── tool/                       # DTCS runtime config
│   ├── env.sh
│   └── pyproject.toml
└── scripts/                    # Deploy & verify
    ├── deploy-nano-isaac.sh
    └── verify-nano-isaac.sh
```

## Adapting from Upstream

The nanoISAAC repo uses Claude Code's `.claude/skills/*/SKILL.md` convention. Adapting to the shared deployment required:

### Path rewrites

| Upstream pattern | Deployed pattern |
|-----------------|-----------------|
| `.claude/skills/binding_energies/data.json` | `/sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/binding_energies.json` |
| `python .claude/skills/reaction_parameters/reaction_db.py` | `nano_isaac_run python /sdf/.../data/nano-isaac/scripts/reaction_db.py` |
| `uv run python script.py` | `source .../tools/nano-isaac/env.sh && nano_isaac_run python script.py` |
| `workspace/simulation.py` | `/tmp/nano-isaac-$USER/simulation.py` |

### Data file resolution trick

`reaction_db.py` finds its data via `Path(__file__).parent / "data.json"`. In the deployed layout, the script is at `data/nano-isaac/scripts/reaction_db.py` but the data is at `data/nano-isaac/reaction_parameters.json`. The deploy script creates a symlink `scripts/data.json -> ../reaction_parameters.json` to bridge this without modifying the upstream script.

### Dropped dependencies

The upstream pyproject.toml includes `edison-client`, `modal`, `httpx`, `pydantic`, `python-dotenv` for optional external services. The deployed version trims to DTCS runtime deps only, since Edison (requires API key) and Modal (requires account) are not available to all users.

## Gotchas Encountered

### 1. Absolute paths in SKILL.md sub-skill routing

**Problem:** The SKILL.md routing table initially used relative markdown links like `[binding-energies](sub-skills/binding-energies.md)`. The OpenCode agent resolved these against the wrong base path (e.g., `tools/nano-isaac/skills/nano-isaac/sub-skills/` instead of `opencode/skills/nano-isaac/sub-skills/`).

**Fix:** Use absolute paths in the routing table:
```markdown
| binding-energies | `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/nano-isaac/sub-skills/binding-energies.md` | ... |
```

### 2. `pkg_resources` removed from setuptools 82+

**Problem:** DTCS imports `pkg_resources` (via `dtcs.examples`), which was split out of setuptools in v82. The import fails with `ModuleNotFoundError: No module named 'pkg_resources'`.

**Fix:** Pin `setuptools<81` in pyproject.toml dependencies.

### 3. Hidden IPython dependency

**Problem:** DTCS imports `IPython.core.interactiveshell` at module load time (via `dtcs.common.display.ctk`). This wasn't in the trimmed dependency list.

**Fix:** Add `ipython` to pyproject.toml dependencies.

### 4. Python version compatibility

**Problem:** `uv sync` picked Python 3.14 (the newest available), but `pkg_resources` was fully removed from the stdlib in 3.12+. Even with `setuptools<81`, there can be compatibility issues.

**Fix:** Pin `requires-python = ">=3.11,<3.13"` in pyproject.toml. Python 3.11 is available in the shared deployment at `/sdf/group/lcls/ds/dm/apps/dev/python/`.

### 5. Discovering hidden dependencies

**General lesson:** Trimming a dependency list from an upstream project is risky. Libraries may have transitive imports that only surface at runtime. The verify script with an actual import test (`from dtcs.spec.xps import XPSSpeciesManager`) was essential for catching these. Always test the actual import path the agent will use, not just `import dtcs`.

## Deploy and Verify Scripts

### deploy-nano-isaac.sh

The deploy script does 6 steps:
1. Copies skill files -> `opencode/skills/nano-isaac/`
2. Copies data files from nanoISAAC repo -> `data/nano-isaac/` (with symlink trick)
3. Copies tool files -> `tools/nano-isaac/`
4. Runs `uv sync` if `.venv` doesn't exist
5. Creates agent symlink `agents/nano-isaac -> ../skills/nano-isaac`
6. Fixes permissions: `chgrp -R ps-data` + `chmod -R g+rX`

Accepts `--upstream /path/to/nanoISAAC` flag (defaults to `/tmp/nanoISAAC`).

### verify-nano-isaac.sh

Checks 28 items across 6 categories: skills (10 files), agent (symlink exists + target), data (9 files + symlink resolution), tool (3 items), DTCS (3 import tests), permissions (3 group checks). Returns exit code = number of failures.

## CLAUDE.md Updates

Four sections need entries when adding a new skill:

1. **Deployed Directory Structure** — add rows for skills/, data/, tools/
2. **Source -> Deploy Mapping** — add rows mapping deployed paths to source paths
3. **Key Config Details** — add a line describing env.sh variables and wrapper function
4. **Agent/Skill Config Locations** — add a subsection with the table of all copies

## Running the Deploy

```bash
# Clone upstream if needed
git clone git@github.com:ISAAC-DOE/nanoISAAC.git /tmp/nanoISAAC

# Deploy
bash /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode/claude/skills/nano-isaac/scripts/deploy-nano-isaac.sh

# Verify
bash /sdf/group/lcls/ds/dm/apps/dev/opencode/skills/nano-isaac/scripts/verify-nano-isaac.sh

# Quick smoke test
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh
nano_isaac_run python -c "
from dtcs.spec.xps import XPSSpeciesManager
from dtcs.spec.crn.bulk import CRNSpec, Rxn, Conc
sm = XPSSpeciesManager()
a = sm.make_species('A', 530.0, color='red')
b = sm.make_species('B', 531.0, color='blue')
c = sm.make_species('C', 532.0, color='green')
crn = CRNSpec(Rxn(a+b, c, k=1.0), Rxn(c, a+b, k=0.5), Conc(a, 1.0), Conc(b, 1.0), sm, time=10)
cts = crn.simulate()
print(f'Final: A={cts.df.iloc[-1][a]:.3f} (expect 0.500)')
"

# Test in opencode:
#   @nano-isaac What binding energies should I expect for O 1s on Ag(110)?
```
