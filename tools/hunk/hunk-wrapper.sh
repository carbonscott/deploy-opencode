#!/usr/bin/env bash
# Shared hunk for S3DF (https://github.com/modem-dev/hunk).
#
# tools/hunk/install-hunk.sh copies this file to $DEPLOY_ROOT/hunk/bin/hunk and
# links $DEPLOY_ROOT/bin/hunk to it. It runs $DEPLOY_ROOT/hunk/current/bin/hunk
# with three defaults for a shared login node:
#
#  1. A per-user session port. Hunk's session daemon listens on 127.0.0.1:47657
#     unless HUNK_MCP_PORT says otherwise, and a port is per HOST, so the first
#     user to open Hunk on a login node would block everyone else. Here the port
#     is 21000 + (uid % 10000), below the 32768+ ephemeral range. A
#     HUNK_MCP_PORT you set yourself wins. The viewer in your terminal and the
#     agent's `hunk session` calls must use the same port, so a PERSONAL hunk
#     install needs the same line in your shell startup file:
#       export HUNK_MCP_PORT=$((21000 + $(id -u) % 10000))
#     The daemon checks signed per-user keys, so a clash with another user's
#     port fails closed: it cannot read or drive your sessions.
#  2. No startup update check (HUNK_DISABLE_UPDATE_NOTICE=1), which would
#     otherwise contact hunk.dev every few hours.
#  3. `hunk update` is refused: this copy is upgraded centrally.

set -euo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
real="$here/../current/bin/hunk"
if [ ! -x "$real" ]; then
  echo "hunk: shared install is incomplete ($real is missing)" >&2
  exit 127
fi

if [ -z "${HUNK_MCP_PORT:-}" ]; then
  HUNK_MCP_PORT=$((21000 + $(id -u) % 10000))
  export HUNK_MCP_PORT
fi
export HUNK_DISABLE_UPDATE_NOTICE="${HUNK_DISABLE_UPDATE_NOTICE:-1}"

if [ "${1:-}" = "update" ]; then
  echo "hunk: this is the shared S3DF copy ($(readlink -f "$real")); it is upgraded" >&2
  echo "      centrally with deploy-opencode tools/hunk/install-hunk.sh. Ask the" >&2
  echo "      maintainers, or install your own copy (https://hunk.dev)." >&2
  exit 1
fi

exec "$real" "$@"
