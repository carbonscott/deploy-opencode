#!/usr/bin/env bash
# Deploy the sandbox SIF and launcher to the shared location.
#
# Usage:
#   ./deploy.sh           # deploy SIF + launcher
#   ./deploy.sh --dry-run # show what would be copied
#
# Requires: SIF built (run build.sh first), write access to deploy dir.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIF_FILE="${SCRIPT_DIR}/opencode-sandbox.sif"
LAUNCHER="${SCRIPT_DIR}/bin/opencode-sandbox"

DEPLOY_BASE="/sdf/group/lcls/ds/dm/apps/dev"
DEPLOY_BIN="${DEPLOY_BASE}/bin"
DEPLOY_SIF="${DEPLOY_BASE}/bin/opencode-sandbox.sif"
DEPLOY_LAUNCHER="${DEPLOY_BIN}/opencode-sandbox"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Validate source files exist
if [[ ! -f "$SIF_FILE" ]]; then
    echo "Error: SIF not found: $SIF_FILE" >&2
    echo "Run build.sh first." >&2
    exit 1
fi

if [[ ! -f "$LAUNCHER" ]]; then
    echo "Error: launcher not found: $LAUNCHER" >&2
    exit 1
fi

if [[ ! -d "$DEPLOY_BIN" ]]; then
    echo "Error: deploy directory does not exist: $DEPLOY_BIN" >&2
    exit 1
fi

echo "Deploying sandbox to ${DEPLOY_BASE} ..."

if $DRY_RUN; then
    echo "[dry-run] Would copy: $SIF_FILE -> $DEPLOY_SIF"
    echo "[dry-run] Would copy: $LAUNCHER -> $DEPLOY_LAUNCHER"
    echo "[dry-run] Would fix permissions (chgrp ps-users, chmod g+rX)"
    exit 0
fi

# Copy SIF
echo "Copying SIF ..."
cp "$SIF_FILE" "$DEPLOY_SIF"

# Copy launcher
echo "Copying launcher ..."
cp "$LAUNCHER" "$DEPLOY_LAUNCHER"
chmod +x "$DEPLOY_LAUNCHER"

# Fix permissions for group access.
# Group MUST be ps-users (~3744 employees), NOT ps-data (~60): these files are
# not world-readable, so the group owner is how the broad employee population
# gets access. Using ps-data here locks out everyone not in that small group.
echo "Fixing permissions ..."
chgrp ps-users "$DEPLOY_SIF" "$DEPLOY_LAUNCHER"
chmod g+rX "$DEPLOY_SIF" "$DEPLOY_LAUNCHER"

echo ""
echo "Deployed:"
ls -lh "$DEPLOY_SIF"
ls -lh "$DEPLOY_LAUNCHER"
echo ""
echo "Users can now run: ${DEPLOY_LAUNCHER}"
