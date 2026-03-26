#!/bin/bash
#
# epics-docs-cron.sh — Cron wrapper for epics-docs sync (git pull + re-index)
#
# Usage:
#   ./epics-docs-cron.sh status              Show cron and data status
#   ./epics-docs-cron.sh enable              Add cron entry on sdfcron001
#   ./epics-docs-cron.sh disable             Remove cron entry from sdfcron001
#   ./epics-docs-cron.sh run                 Run sync now

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source env.sh (sets EPICS_DOCS_APP_DIR, EPICS_DOCS_DATA_DIR, PATH, etc.)
source "$PROJECT_DIR/env.sh"

# Cron configuration
CRON_NODE="${CRON_NODE:-sdfcron001}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 3 * * 0}"
CRON_LOG="${CRON_LOG:-$EPICS_DOCS_DATA_DIR/cron.log}"
CRON_MARKER="epics-docs-cron.sh"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

run_sync() {
    # Pull latest changes for all repos
    local repo_count=0
    local fail_count=0
    for repo_dir in "$EPICS_DOCS_DATA_DIR"/*/; do
        [[ -d "$repo_dir/.git" ]] || continue
        repo_name=$(basename "$repo_dir")
        log "Pulling $repo_name..."
        if git -C "$repo_dir" pull --ff-only 2>&1; then
            repo_count=$((repo_count + 1))
        else
            log "WARNING: git pull failed for $repo_name"
            fail_count=$((fail_count + 1))
        fi
    done
    log "Pulled $repo_count repos ($fail_count failures)"

    # Rebuild search index (incremental — only changed files)
    docs-index index "$EPICS_DOCS_DATA_DIR" --incremental \
        --ext hpp java h c cpp py md dbd txt pl rst sh

    # Fix permissions for shared access
    chgrp -R ps-data "$EPICS_DOCS_DATA_DIR"
    chmod -R g+rX "$EPICS_DOCS_DATA_DIR"
}

# --- Commands ---

cmd_status() {
    echo "=== Cron Status (on $CRON_NODE) ==="
    if ssh "$CRON_NODE" "crontab -l 2>/dev/null" 2>/dev/null | grep -q "$CRON_MARKER"; then
        echo "Cron: ENABLED"
        ssh "$CRON_NODE" "crontab -l" 2>/dev/null | grep "$CRON_MARKER"
    else
        echo "Cron: DISABLED (or cannot reach $CRON_NODE)"
    fi

    echo ""
    echo "=== Data Directory ==="
    echo "Path: $EPICS_DOCS_DATA_DIR"
    local repo_count
    repo_count=$(find "$EPICS_DOCS_DATA_DIR" -maxdepth 2 -name .git -type d 2>/dev/null | wc -l)
    echo "Git repos: $repo_count"

    if [[ -f "$EPICS_DOCS_DATA_DIR/search.db" ]]; then
        echo "Search index: $(du -h "$EPICS_DOCS_DATA_DIR/search.db" | cut -f1)"
        docs-index info "$EPICS_DOCS_DATA_DIR" 2>/dev/null | grep "Indexed documents:" || true
    else
        echo "Search index: NOT FOUND"
    fi

    echo ""
    echo "=== Recent Log Entries ==="
    if [[ -f "$CRON_LOG" ]]; then
        tail -10 "$CRON_LOG"
    else
        echo "(no log file yet)"
    fi
}

cmd_enable() {
    local cron_entry="$CRON_SCHEDULE $SCRIPT_DIR/epics-docs-cron.sh run >> $CRON_LOG 2>&1"

    echo "Enabling cron on $CRON_NODE..."
    echo "Schedule: $CRON_SCHEDULE"
    echo "Entry: $cron_entry"

    ssh "$CRON_NODE" bash -c "'
        # Remove old entry if exists
        if crontab -l 2>/dev/null | grep -q \"$CRON_MARKER\"; then
            echo \"Removing old entry first\"
            crontab -l | grep -v \"$CRON_MARKER\" | crontab -
        fi
        # Add new entry
        (crontab -l 2>/dev/null; echo \"$cron_entry\") | crontab -
        echo \"Cron entry added:\"
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

cmd_run() {
    log "========================================"
    log "epics-docs sync starting"
    log "========================================"
    log "DATA_DIR: $EPICS_DOCS_DATA_DIR"

    run_sync

    log "========================================"
    log "epics-docs sync complete"
    log "========================================"
}

# --- Main ---
if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") {status|enable|disable|run}"
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
    status)  cmd_status ;;
    enable)  cmd_enable ;;
    disable) cmd_disable ;;
    run)     cmd_run "$@" ;;
    *)       echo "Unknown command: $COMMAND" >&2; exit 1 ;;
esac
