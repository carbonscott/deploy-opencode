#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/run/proxy.pid"

if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Proxy is not running"
    rm -f "$PID_FILE"
    exit 0
fi

kill "$(cat "$PID_FILE")"
rm -f "$PID_FILE"
echo "Proxy stopped"
