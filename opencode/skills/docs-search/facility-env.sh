#!/bin/bash
# Site detection for docs-search skill.
# Sets DOCS_SEARCH_BIN with a facility-appropriate default.
# Can always be overridden by setting DOCS_SEARCH_BIN before sourcing.

if [ -d /sdf ]; then
    # S3DF (SLAC)
    export DOCS_SEARCH_BIN="${DOCS_SEARCH_BIN:-/sdf/group/lcls/ds/dm/apps/dev/bin}"
elif [ -d /lustre/orion ]; then
    # OLCF (Frontier)
    export DOCS_SEARCH_BIN="${DOCS_SEARCH_BIN:-/ccs/home/cwang31/.local/bin}"
fi

if [ -n "$DOCS_SEARCH_BIN" ]; then
    export PATH="$DOCS_SEARCH_BIN:$PATH"
fi
