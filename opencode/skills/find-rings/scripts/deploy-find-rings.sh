#!/usr/bin/env bash
#
# Deploy find-rings skill to the shared opencode deployment.
#
# Usage:
#   bash deploy-find-rings.sh
#
# What it does:
#   1. Copies skill files (SKILL.md, references/) -> dev/opencode/skills/find-rings/
#   2. Copies tool files (env.sh, pyproject.toml) -> dev/tools/find-rings/
#   3. Copies scripts (elsd_detect.py, find_rings.py, elsd/) -> dev/tools/find-rings/scripts/
#   4. Runs uv sync to create/update .venv
#   5. Creates agent symlink dev/opencode/agents/find-rings -> ../skills/find-rings
#   6. Fixes permissions (ps-data group, g+rX)

set -euo pipefail

# --- Configuration ---
DEV_BASE="/sdf/group/lcls/ds/dm/apps/dev"
SKILL_DIR="$DEV_BASE/opencode/skills/find-rings"
TOOL_DIR="$DEV_BASE/tools/find-rings"
AGENT_LINK="$DEV_BASE/opencode/agents/find-rings"

# Source directory (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Deploying find-rings (v0.3.0, ELSD-based) ==="
echo "  Source: $SOURCE_DIR"
echo "  Target: $DEV_BASE"
echo ""

# --- Step 1: Copy skill files ---
echo "[1/6] Copying skill files -> $SKILL_DIR"
mkdir -p "$SKILL_DIR/references" "$SKILL_DIR/scripts"
cp "$SOURCE_DIR/SKILL.md" "$SKILL_DIR/"
cp "$SOURCE_DIR/references/spatial-calib-xray.md" "$SKILL_DIR/references/"
# Also copy the deploy/verify scripts so they're accessible from the deployed location
cp "$SOURCE_DIR/scripts/deploy-find-rings.sh" "$SKILL_DIR/scripts/"
cp "$SOURCE_DIR/scripts/verify-find-rings.sh" "$SKILL_DIR/scripts/"
chmod +x "$SKILL_DIR/scripts/"*.sh
echo "  Copied SKILL.md + 1 reference + 2 scripts"

# --- Step 2: Copy tool files ---
echo "[2/6] Copying tool files -> $TOOL_DIR"
mkdir -p "$TOOL_DIR"
cp "$SOURCE_DIR/tool/env.sh" "$TOOL_DIR/"
cp "$SOURCE_DIR/tool/pyproject.toml" "$TOOL_DIR/"
echo "  Copied env.sh + pyproject.toml"

# --- Step 3: Copy Python scripts + ELSD ---
echo "[3/6] Copying scripts -> $TOOL_DIR/scripts/"
mkdir -p "$TOOL_DIR/scripts/elsd"
cp "$SOURCE_DIR/scripts/elsd_detect.py" "$TOOL_DIR/scripts/"
cp "$SOURCE_DIR/scripts/find_rings.py" "$TOOL_DIR/scripts/"
cp -r "$SOURCE_DIR/scripts/elsd/"* "$TOOL_DIR/scripts/elsd/"
chmod +x "$TOOL_DIR/scripts/elsd/elsd" 2>/dev/null || true
echo "  Copied elsd_detect.py + find_rings.py + elsd/ directory"

# --- Step 4: Create/update venv ---
echo "[4/6] Setting up Python environment"
export PATH="$DEV_BASE/bin:$PATH"
export UV_PYTHON_INSTALL_DIR="$DEV_BASE/python"
export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache-$USER}"
if [[ ! -d "$TOOL_DIR/.venv" ]]; then
    echo "  Creating .venv (this may take a minute)..."
    (cd "$TOOL_DIR" && uv sync)
    echo "  .venv created successfully"
else
    echo "  .venv exists, running uv sync to update..."
    (cd "$TOOL_DIR" && uv sync)
    echo "  .venv updated successfully"
fi

# --- Step 5: Create agent symlink ---
echo "[5/6] Creating agent symlink"
mkdir -p "$DEV_BASE/opencode/agents"
ln -sfn ../skills/find-rings "$AGENT_LINK"
echo "  $AGENT_LINK -> ../skills/find-rings"

# --- Step 6: Fix permissions ---
echo "[6/6] Fixing permissions (ps-data group, g+rX)"
for dir in "$SKILL_DIR" "$TOOL_DIR"; do
    chgrp -R ps-data "$dir" 2>/dev/null || echo "  WARNING: chgrp failed on $dir (may need sudo)"
    chmod -R g+rX "$dir" 2>/dev/null || echo "  WARNING: chmod failed on $dir"
done

echo ""
echo "=== Deploy complete ==="
echo ""
echo "To verify: bash $SKILL_DIR/scripts/verify-find-rings.sh"
echo ""
echo "To test:"
echo "  source $TOOL_DIR/env.sh"
echo "  find_rings_run python -c \"import numpy; import scipy; from PIL import Image; print('OK')\""
