#!/bin/bash
# Site detection for ask-epics skill.
# Sets EPICS_DOCS_ROOT with a facility-appropriate default.
# Can always be overridden by setting EPICS_DOCS_ROOT before sourcing.

if [ -d /sdf ]; then
    # S3DF (SLAC)
    export EPICS_DOCS_ROOT="${EPICS_DOCS_ROOT:-/sdf/group/lcls/ds/dm/apps/dev/data/epics-docs}"
    export PATH="/sdf/group/lcls/ds/dm/apps/dev/bin:$PATH"
elif [ -d /lustre/orion ]; then
    # OLCF (Frontier)
    export EPICS_DOCS_ROOT="${EPICS_DOCS_ROOT:-/lustre/orion/lrn091/proj-shared/cwang31/deps/epics-org}"
fi
