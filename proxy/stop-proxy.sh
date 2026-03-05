#!/bin/bash
# Convenience wrapper — stops the proxy via proxy-cron.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/scripts/proxy-cron.sh" stop
