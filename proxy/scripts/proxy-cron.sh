#!/bin/bash
#
# proxy-cron.sh - Manage the API key proxy service
#
# Usage:
#   ./proxy-cron.sh status       Show proxy status, PID, and recent logs
#   ./proxy-cron.sh start        Start the proxy (idempotent)
#   ./proxy-cron.sh stop         Stop the proxy
#   ./proxy-cron.sh restart      Stop + start
#   ./proxy-cron.sh enable       Add @reboot cron entry on sdfcron001
#   ./proxy-cron.sh disable      Remove cron entry from sdfcron001

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source env.sh (one level up from scripts/)
source "$SCRIPT_DIR/../env.sh"

# Configuration
CRON_NODE="${CRON_NODE:-sdfcron001}"
PID_FILE="$PROXY_RUN_DIR/proxy.pid"
LOG_FILE="$PROXY_RUN_DIR/proxy.log"
CRON_MARKER="proxy-cron.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") COMMAND

Commands:
  status       Show proxy status, PID, and recent logs
  start        Start the proxy (idempotent — no-op if already running)
  stop         Stop the proxy
  restart      Stop + start
  enable       Add @reboot cron entry on $CRON_NODE
  disable      Remove cron entry from $CRON_NODE

Environment variables (set in env.sh or env.local):
  PROXY_HOST           Listen address (default: 0.0.0.0)
  PROXY_PORT           Listen port (default: 4000)
  PROXY_API_KEY_FILE   Real API key file
  PROXY_KEY_FILE       Proxy key file
  CRON_NODE            Node for cron job (default: sdfcron001)
EOF
    exit 1
}

is_running() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

cmd_status() {
    echo "=== Proxy Status ==="
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        echo "Status: RUNNING (pid $pid)"
        echo "Listen: $PROXY_HOST:$PROXY_PORT"
    else
        echo "Status: STOPPED"
        rm -f "$PID_FILE"
    fi

    echo ""
    echo "=== Configuration ==="
    echo "API key file:   $PROXY_API_KEY_FILE"
    echo "Proxy key file: $PROXY_KEY_FILE"
    echo "Python:         $PROXY_PYTHON"
    echo "PID file:       $PID_FILE"
    echo "Log file:       $LOG_FILE"

    echo ""
    echo "=== Cron Status (on $CRON_NODE) ==="
    if ssh -o ConnectTimeout=3 -o BatchMode=yes "$CRON_NODE" "crontab -l 2>/dev/null" 2>/dev/null | grep -q "$CRON_MARKER"; then
        echo "Cron: ENABLED"
        ssh -o ConnectTimeout=3 -o BatchMode=yes "$CRON_NODE" "crontab -l" 2>/dev/null | grep "$CRON_MARKER"
    else
        echo "Cron: DISABLED (or $CRON_NODE unreachable)"
    fi

    echo ""
    echo "=== Recent Logs ==="
    if [[ -f "$LOG_FILE" ]]; then
        tail -10 "$LOG_FILE"
    else
        echo "(no log file yet)"
    fi
}

cmd_start() {
    if is_running; then
        echo "Proxy already running (pid $(cat "$PID_FILE"))"
        return 0
    fi

    mkdir -p "$PROXY_RUN_DIR"

    # Validate key files exist
    if [[ ! -f "$PROXY_KEY_FILE" ]]; then
        echo "Error: proxy key file not found: $PROXY_KEY_FILE"
        echo "Create it with:"
        echo "  echo 'choose-a-secret-proxy-key' > $PROXY_KEY_FILE"
        echo "  chmod 600 $PROXY_KEY_FILE"
        exit 1
    fi

    if [[ ! -f "$PROXY_API_KEY_FILE" ]]; then
        echo "Error: API key file not found: $PROXY_API_KEY_FILE"
        exit 1
    fi

    # Start proxy in background
    "$PROXY_PYTHON" "$PROXY_APP_DIR/proxy.py" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "Proxy started on http://$PROXY_HOST:$PROXY_PORT (pid $!)"
    echo "Logs: $LOG_FILE"
}

cmd_stop() {
    if ! is_running; then
        echo "Proxy is not running"
        rm -f "$PID_FILE"
        return 0
    fi

    kill "$(cat "$PID_FILE")"
    rm -f "$PID_FILE"
    echo "Proxy stopped"
}

cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

cmd_enable() {
    local cron_entry="@reboot $SCRIPT_DIR/proxy-cron.sh start >> $LOG_FILE 2>&1"

    echo "Enabling cron on $CRON_NODE..."
    echo "Entry: $cron_entry"
    echo ""

    ssh "$CRON_NODE" bash -c "'
        if crontab -l 2>/dev/null | grep -q \"$CRON_MARKER\"; then
            echo \"Cron entry already exists - replacing\"
            crontab -l | grep -v \"$CRON_MARKER\" | crontab -
        fi
        (crontab -l 2>/dev/null; echo \"$cron_entry\") | crontab -
        echo \"Cron entry added\"
        echo \"\"
        echo \"Current crontab:\"
        crontab -l | grep \"$CRON_MARKER\" || true
    '"
}

cmd_disable() {
    echo "Disabling cron on $CRON_NODE..."

    ssh "$CRON_NODE" bash -c "'
        if crontab -l 2>/dev/null | grep -q \"$CRON_MARKER\"; then
            crontab -l | grep -v \"$CRON_MARKER\" | crontab -
            echo \"Cron entry removed\"
        else
            echo \"No cron entry found\"
        fi
    '"
}

# --- Main ---
if [[ $# -lt 1 ]]; then
    usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
    status)   cmd_status ;;
    start|run) cmd_start ;;
    stop)     cmd_stop ;;
    restart)  cmd_restart ;;
    enable)   cmd_enable ;;
    disable)  cmd_disable ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        usage
        ;;
esac
