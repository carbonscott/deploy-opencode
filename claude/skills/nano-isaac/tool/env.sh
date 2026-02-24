# nano-isaac environment setup

# Add shared uv to PATH
export PATH="/sdf/group/lcls/ds/dm/apps/dev/bin:$PATH"

# Use shared Python installs
export UV_PYTHON_INSTALL_DIR="/sdf/group/lcls/ds/dm/apps/dev/python"

# Auto-detect project directory
export NANO_ISAAC_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Data directory
export NANO_ISAAC_DATA_DIR="/sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac"

# UV cache per-user in /tmp
export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache-$USER}"

# Source local overrides
if [[ -f "$NANO_ISAAC_APP_DIR/env.local" ]]; then
    source "$NANO_ISAAC_APP_DIR/env.local"
fi

# Convenience wrapper: run Python (or any command) in the nano-isaac venv
nano_isaac_run() {
    uv run --frozen --project "$NANO_ISAAC_APP_DIR" "$@"
}
