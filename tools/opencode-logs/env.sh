#!/bin/bash
# Environment configuration for the OpenCode log ingest tool.
# Sources env.local for deployment-specific overrides.
#
# ingest_opencode_logs.py is a PEP 723 script (inline `dependencies = ["duckdb"]`)
# with no shebang, so it is always run as `uv run ingest_opencode_logs.py`.
# Sourcing this file first makes that `uv` the shared one in the deployment tree
# rather than whichever personal install happens to be on PATH.

# Add shared uv to PATH
export PATH="/sdf/group/lcls/ds/dm/apps/dev/bin:$PATH"

# Use shared Python installs
export UV_PYTHON_INSTALL_DIR="/sdf/group/lcls/ds/dm/apps/dev/python"

# UV cache per-user in /tmp
export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache-$USER}"

export OPENCODE_LOGS_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$OPENCODE_LOGS_APP_DIR/env.local" ]]; then
    source "$OPENCODE_LOGS_APP_DIR/env.local"
fi
