# API key proxy environment setup

# Add shared uv to PATH
export PATH="/sdf/group/lcls/ds/dm/apps/dev/bin:$PATH"

# Use shared Python installs
export UV_PYTHON_INSTALL_DIR="/sdf/group/lcls/ds/dm/apps/dev/python"

# UV cache per-user in /tmp
export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache-$USER}"

# Auto-detect project directory
export PROXY_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Runtime directory (PID file, logs, proxy key)
export PROXY_RUN_DIR="${PROXY_RUN_DIR:-$PROXY_APP_DIR/run}"

# Proxy settings
export PROXY_HOST="${PROXY_HOST:-0.0.0.0}"
export PROXY_PORT="${PROXY_PORT:-4000}"

# Key files
export PROXY_API_KEY_FILE="${PROXY_API_KEY_FILE:-/sdf/group/lcls/ds/dm/apps/dev/env/key.dat}"
export PROXY_KEY_FILE="${PROXY_KEY_FILE:-$PROXY_RUN_DIR/proxy-key.dat}"

# Python for running the proxy
export PROXY_PYTHON="${PROXY_PYTHON:-/sdf/group/lcls/ds/dm/apps/dev/python/cpython-3.11.14-linux-x86_64-gnu/bin/python3}"

# Source local overrides
if [[ -f "$PROXY_APP_DIR/env.local" ]]; then
    source "$PROXY_APP_DIR/env.local"
fi
