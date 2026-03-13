#!/usr/bin/env bash
# Build the opencode-sandbox Apptainer SIF image.
#
# Usage:
#   ./build.sh              # builds sandbox/opencode-sandbox.sif
#   ./build.sh --force      # rebuild even if SIF already exists
#
# Tries --fakeroot first (works if unprivileged user namespaces are enabled).
# If that fails, prints instructions for building on a machine with root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEF_FILE="${SCRIPT_DIR}/opencode-sandbox.def"
SIF_FILE="${SCRIPT_DIR}/opencode-sandbox.sif"

if [[ ! -f "$DEF_FILE" ]]; then
    echo "Error: definition file not found: $DEF_FILE" >&2
    exit 1
fi

if [[ -f "$SIF_FILE" && "${1:-}" != "--force" ]]; then
    echo "SIF already exists: $SIF_FILE"
    echo "Use --force to rebuild."
    exit 0
fi

echo "Building SIF from $DEF_FILE ..."
echo "Attempting apptainer build --fakeroot ..."

if apptainer build --fakeroot "$SIF_FILE" "$DEF_FILE"; then
    echo "Build succeeded: $SIF_FILE"
    ls -lh "$SIF_FILE"
else
    echo ""
    echo "ERROR: --fakeroot build failed." >&2
    echo "" >&2
    echo "This likely means unprivileged user namespaces are not enabled on this host." >&2
    echo "Options:" >&2
    echo "  1. Build on a machine with root access:" >&2
    echo "       sudo apptainer build opencode-sandbox.sif opencode-sandbox.def" >&2
    echo "       scp opencode-sandbox.sif <s3df-host>:${SCRIPT_DIR}/" >&2
    echo "  2. Ask IT to enable unprivileged user namespaces." >&2
    exit 1
fi
