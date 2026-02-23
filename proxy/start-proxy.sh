#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$SCRIPT_DIR/run"
PYTHON="/sdf/group/lcls/ds/dm/apps/dev/python/cpython-3.11.14-linux-x86_64-gnu/bin/python3"
PID_FILE="$RUN_DIR/proxy.pid"

# Check if already running
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Proxy already running (pid $(cat "$PID_FILE"))"
    exit 0
fi

mkdir -p "$RUN_DIR"

# Check proxy key exists
PROXY_KEY_FILE="$RUN_DIR/proxy-key.dat"
if [ ! -f "$PROXY_KEY_FILE" ]; then
    echo "Error: proxy key file not found: $PROXY_KEY_FILE"
    echo "Create it with a chosen key, e.g.:"
    echo "  echo 'my-secret-proxy-key' > $PROXY_KEY_FILE"
    echo "  chmod 600 $PROXY_KEY_FILE"
    exit 1
fi

# Start proxy in background
"$PYTHON" "$SCRIPT_DIR/proxy.py" > "$RUN_DIR/proxy.log" 2>&1 &
echo $! > "$PID_FILE"
echo "Proxy started on http://127.0.0.1:4000 (pid $!)"
echo "Logs: $RUN_DIR/proxy.log"
