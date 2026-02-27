# find-rings environment setup

# Add shared uv to PATH
export PATH="/sdf/group/lcls/ds/dm/apps/dev/bin:$PATH"

# Use shared Python installs
export UV_PYTHON_INSTALL_DIR="/sdf/group/lcls/ds/dm/apps/dev/python"

# Auto-detect project directory
export FIND_RINGS_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# UV cache per-user in /tmp
export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache-$USER}"

# Source local overrides
if [[ -f "$FIND_RINGS_APP_DIR/env.local" ]]; then
    source "$FIND_RINGS_APP_DIR/env.local"
fi

# Convenience wrapper: run Python (or any command) in the find-rings venv
find_rings_run() {
    uv run --frozen --project "$FIND_RINGS_APP_DIR" "$@"
}
