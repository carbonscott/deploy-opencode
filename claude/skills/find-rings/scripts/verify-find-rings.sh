#!/usr/bin/env bash
#
# Verify find-rings skill deployment.
#
# Usage:
#   bash verify-find-rings.sh
#
# Returns: exit code = number of failures (0 = all good)

set -uo pipefail

DEV_BASE="/sdf/group/lcls/ds/dm/apps/dev"
SKILL_DIR="$DEV_BASE/opencode/skills/find-rings"
TOOL_DIR="$DEV_BASE/tools/find-rings"
AGENT_LINK="$DEV_BASE/opencode/agents/find-rings"

FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  OK  $desc"
    else
        echo "  FAIL $desc"
        ((FAIL++))
    fi
}

echo "=== Verifying find-rings deployment ==="
echo ""

# Skill files
echo "[Skill files]"
check "SKILL.md exists" test -f "$SKILL_DIR/SKILL.md"
check "references/spatial-calib-xray.md exists" test -f "$SKILL_DIR/references/spatial-calib-xray.md"
check "scripts/deploy-find-rings.sh exists" test -f "$SKILL_DIR/scripts/deploy-find-rings.sh"
check "scripts/verify-find-rings.sh exists" test -f "$SKILL_DIR/scripts/verify-find-rings.sh"

# Agent symlink
echo ""
echo "[Agent symlink]"
check "agents/find-rings symlink exists" test -L "$AGENT_LINK"
check "agents/find-rings points to ../skills/find-rings" test "$(readlink "$AGENT_LINK")" = "../skills/find-rings"

# Tool files
echo ""
echo "[Tool files]"
check "env.sh exists" test -f "$TOOL_DIR/env.sh"
check "pyproject.toml exists" test -f "$TOOL_DIR/pyproject.toml"
check "scripts/elsd_detect.py exists" test -f "$TOOL_DIR/scripts/elsd_detect.py"
check "scripts/find_rings.py exists" test -f "$TOOL_DIR/scripts/find_rings.py"
check "scripts/elsd/elsd binary exists" test -f "$TOOL_DIR/scripts/elsd/elsd"
check "scripts/elsd/elsd binary is executable" test -x "$TOOL_DIR/scripts/elsd/elsd"
check ".venv exists" test -d "$TOOL_DIR/.venv"

# Python imports
echo ""
echo "[Python imports]"
source "$TOOL_DIR/env.sh"
check "numpy importable" find_rings_run python -c "import numpy"
check "Pillow importable" find_rings_run python -c "from PIL import Image"
check "scipy importable" find_rings_run python -c "import scipy"
check "spatial-calib-xray importable" find_rings_run python -c "from spatial_calib_xray.model import OptimizeConcentricCircles"

# Permissions
echo ""
echo "[Permissions]"
check "skill dir group is ps-data" test "$(stat -c %G "$SKILL_DIR" 2>/dev/null || stat -f %Sg "$SKILL_DIR" 2>/dev/null)" = "ps-data"
check "tool dir group is ps-data" test "$(stat -c %G "$TOOL_DIR" 2>/dev/null || stat -f %Sg "$TOOL_DIR" 2>/dev/null)" = "ps-data"

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo "=== All checks passed ==="
else
    echo "=== $FAIL check(s) failed ==="
fi

exit $FAIL
