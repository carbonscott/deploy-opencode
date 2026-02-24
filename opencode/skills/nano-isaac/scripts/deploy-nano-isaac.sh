#!/usr/bin/env bash
#
# Deploy nanoISAAC skill to the shared opencode deployment.
#
# Usage:
#   bash deploy-nano-isaac.sh [--upstream /path/to/nanoISAAC]
#
# What it does:
#   1. Copies skill files (SKILL.md, sub-skills/, references/) -> dev/opencode/skills/nano-isaac/
#   2. Copies data files from nanoISAAC repo -> dev/data/nano-isaac/
#   3. Copies tool files (env.sh, pyproject.toml) -> dev/tools/nano-isaac/
#   4. Runs uv sync if .venv doesn't exist
#   5. Creates agent symlink dev/opencode/agents/nano-isaac -> ../skills/nano-isaac
#   6. Fixes permissions (ps-data group, g+rX)

set -euo pipefail

# --- Configuration ---
DEV_BASE="/sdf/group/lcls/ds/dm/apps/dev"
SKILL_DIR="$DEV_BASE/opencode/skills/nano-isaac"
DATA_DIR="$DEV_BASE/data/nano-isaac"
TOOL_DIR="$DEV_BASE/tools/nano-isaac"
AGENT_LINK="$DEV_BASE/opencode/agents/nano-isaac"

# Source directory (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# nanoISAAC upstream repo (for data files)
UPSTREAM="/tmp/nanoISAAC"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --upstream)
            UPSTREAM="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--upstream /path/to/nanoISAAC]"
            exit 1
            ;;
    esac
done

# --- Validate ---
if [[ ! -d "$SOURCE_DIR/sub-skills" ]]; then
    echo "ERROR: Cannot find sub-skills/ in $SOURCE_DIR"
    echo "       Run this script from the nano-isaac skill directory."
    exit 1
fi

if [[ ! -d "$UPSTREAM" ]]; then
    echo "ERROR: nanoISAAC repo not found at $UPSTREAM"
    echo "       Clone it first: git clone git@github.com:ISAAC-DOE/nanoISAAC.git $UPSTREAM"
    echo "       Or specify: $0 --upstream /path/to/nanoISAAC"
    exit 1
fi

echo "=== Deploying nanoISAAC ==="
echo "  Source:   $SOURCE_DIR"
echo "  Upstream: $UPSTREAM"
echo "  Target:   $DEV_BASE"
echo ""

# --- Step 1: Copy skill files ---
echo "[1/6] Copying skill files -> $SKILL_DIR"
mkdir -p "$SKILL_DIR/sub-skills" "$SKILL_DIR/references"
cp "$SOURCE_DIR/SKILL.md" "$SKILL_DIR/"
cp "$SOURCE_DIR/sub-skills/"*.md "$SKILL_DIR/sub-skills/"
cp "$SOURCE_DIR/references/"*.md "$SKILL_DIR/references/"
# Also copy the deploy/verify scripts so they're accessible from the deployed location
mkdir -p "$SKILL_DIR/scripts"
cp "$SOURCE_DIR/scripts/"*.sh "$SKILL_DIR/scripts/"
chmod +x "$SKILL_DIR/scripts/"*.sh
echo "  Copied SKILL.md + $(ls "$SKILL_DIR/sub-skills/"*.md | wc -l) sub-skills + $(ls "$SKILL_DIR/references/"*.md | wc -l) references"

# --- Step 2: Copy data files from upstream nanoISAAC repo ---
echo "[2/6] Copying data files -> $DATA_DIR"
mkdir -p "$DATA_DIR/scripts" "$DATA_DIR/experimental"

# JSON databases
cp "$UPSTREAM/.claude/skills/binding_energies/data.json" "$DATA_DIR/binding_energies.json"
cp "$UPSTREAM/.claude/skills/reaction_parameters/data.json" "$DATA_DIR/reaction_parameters.json"
cp "$UPSTREAM/.claude/skills/edison_search/cache.json" "$DATA_DIR/edison_cache.json"
cp "$UPSTREAM/.claude/skills/edison_search/config.json" "$DATA_DIR/edison_config.json"

# Python scripts
cp "$UPSTREAM/.claude/skills/reaction_parameters/reaction_db.py" "$DATA_DIR/scripts/reaction_db.py"
cp "$UPSTREAM/.claude/skills/vamas-xps/scripts/vamas_parser.py" "$DATA_DIR/scripts/vamas_parser.py"

# Create symlink so reaction_db.py can find its data via Path(__file__).parent / "data.json"
ln -sf ../reaction_parameters.json "$DATA_DIR/scripts/data.json"

# Experimental data
if [[ -d "$UPSTREAM/data/experimental" ]]; then
    cp "$UPSTREAM/data/experimental/"* "$DATA_DIR/experimental/" 2>/dev/null || true
fi

echo "  Copied 4 JSON files, 2 scripts, experimental data"
echo "  Created scripts/data.json -> ../reaction_parameters.json symlink"

# --- Step 3: Copy tool files ---
echo "[3/6] Copying tool files -> $TOOL_DIR"
mkdir -p "$TOOL_DIR"
cp "$SOURCE_DIR/tool/env.sh" "$TOOL_DIR/"
cp "$SOURCE_DIR/tool/pyproject.toml" "$TOOL_DIR/"
echo "  Copied env.sh + pyproject.toml"

# --- Step 4: Create venv if needed ---
echo "[4/6] Checking Python environment"
if [[ ! -d "$TOOL_DIR/.venv" ]]; then
    echo "  Creating .venv (this may take a minute)..."
    export PATH="$DEV_BASE/bin:$PATH"
    export UV_PYTHON_INSTALL_DIR="$DEV_BASE/python"
    export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache-$USER}"
    (cd "$TOOL_DIR" && uv sync)
    echo "  .venv created successfully"
else
    echo "  .venv already exists, skipping uv sync"
fi

# --- Step 5: Create agent symlink ---
echo "[5/6] Creating agent symlink"
mkdir -p "$DEV_BASE/opencode/agents"
ln -sfn ../skills/nano-isaac "$AGENT_LINK"
echo "  $AGENT_LINK -> ../skills/nano-isaac"

# --- Step 6: Fix permissions ---
echo "[6/6] Fixing permissions (ps-data group, g+rX)"
for dir in "$SKILL_DIR" "$DATA_DIR" "$TOOL_DIR"; do
    chgrp -R ps-data "$dir" 2>/dev/null || echo "  WARNING: chgrp failed on $dir (may need sudo)"
    chmod -R g+rX "$dir" 2>/dev/null || echo "  WARNING: chmod failed on $dir"
done

echo ""
echo "=== Deploy complete ==="
echo ""
echo "To verify: bash $SKILL_DIR/scripts/verify-nano-isaac.sh"
echo ""
echo "To test DTCS:"
echo "  source $TOOL_DIR/env.sh"
echo "  nano_isaac_run python -c \"from dtcs.spec.xps import XPSSpeciesManager; print('DTCS OK')\""
