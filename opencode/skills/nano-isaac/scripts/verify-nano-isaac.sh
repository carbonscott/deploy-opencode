#!/usr/bin/env bash
#
# Verify nanoISAAC deployment.
# Returns exit code = number of failures (0 = all OK).
#
# Usage:
#   bash verify-nano-isaac.sh

set -uo pipefail

DEV_BASE="/sdf/group/lcls/ds/dm/apps/dev"
SKILL_DIR="$DEV_BASE/opencode/skills/nano-isaac"
DATA_DIR="$DEV_BASE/data/nano-isaac"
TOOL_DIR="$DEV_BASE/tools/nano-isaac"
AGENT_LINK="$DEV_BASE/opencode/agents/nano-isaac"

FAILURES=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  OK  $desc"
    else
        echo "  FAIL $desc"
        FAILURES=$((FAILURES + 1))
    fi
}

echo "=== Verifying nanoISAAC deployment ==="
echo ""

# --- Skill files ---
echo "[Skills]"
check "SKILL.md exists" test -f "$SKILL_DIR/SKILL.md"
for sub in binding-energies catalysis-fundamentals crn-generation edison-search \
           mlip-property-prediction reaction-parameters spectrum-analysis vamas-xps; do
    check "sub-skills/$sub.md exists" test -f "$SKILL_DIR/sub-skills/$sub.md"
done
check "references/xps_interpretation.md exists" test -f "$SKILL_DIR/references/xps_interpretation.md"
echo ""

# --- Agent symlink ---
echo "[Agent]"
check "agents/nano-isaac symlink exists" test -L "$AGENT_LINK"
check "agents/nano-isaac points to ../skills/nano-isaac" test "$(readlink "$AGENT_LINK")" = "../skills/nano-isaac"
echo ""

# --- Data files ---
echo "[Data]"
check "binding_energies.json exists" test -f "$DATA_DIR/binding_energies.json"
check "reaction_parameters.json exists" test -f "$DATA_DIR/reaction_parameters.json"
check "edison_cache.json exists" test -f "$DATA_DIR/edison_cache.json"
check "edison_config.json exists" test -f "$DATA_DIR/edison_config.json"
check "scripts/reaction_db.py exists" test -f "$DATA_DIR/scripts/reaction_db.py"
check "scripts/vamas_parser.py exists" test -f "$DATA_DIR/scripts/vamas_parser.py"
check "scripts/data.json symlink exists" test -L "$DATA_DIR/scripts/data.json"
check "scripts/data.json symlink resolves" test -f "$DATA_DIR/scripts/data.json"
check "experimental/ directory exists" test -d "$DATA_DIR/experimental"
echo ""

# --- Tool files ---
echo "[Tool]"
check "pyproject.toml exists" test -f "$TOOL_DIR/pyproject.toml"
check "env.sh exists" test -f "$TOOL_DIR/env.sh"
check ".venv directory exists" test -d "$TOOL_DIR/.venv"
echo ""

# --- DTCS import test ---
echo "[DTCS]"
source "$TOOL_DIR/env.sh" 2>/dev/null
check "DTCS is importable" nano_isaac_run python -c "from dtcs.spec.xps import XPSSpeciesManager"
check "vamas is importable" nano_isaac_run python -c "from vamas import Vamas"
check "pandas is importable" nano_isaac_run python -c "import pandas"
echo ""

# --- Permissions ---
echo "[Permissions]"
check "skill dir is ps-data group" test "$(stat -c '%G' "$SKILL_DIR" 2>/dev/null)" = "ps-data"
check "data dir is ps-data group" test "$(stat -c '%G' "$DATA_DIR" 2>/dev/null)" = "ps-data"
check "tool dir is ps-data group" test "$(stat -c '%G' "$TOOL_DIR" 2>/dev/null)" = "ps-data"
echo ""

# --- Summary ---
if [[ $FAILURES -eq 0 ]]; then
    echo "=== All checks passed ==="
else
    echo "=== $FAILURES check(s) failed ==="
fi

exit $FAILURES
