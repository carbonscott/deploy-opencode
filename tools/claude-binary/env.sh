#!/bin/bash
# Environment configuration for the shared Claude Code binary publisher.
# Sources env.local for deployment-specific overrides.
#
# This tool downloads a pinned Claude Code release, verifies it against
# Anthropic's published SHA-256, and publishes it into the live deployment so
# every ps-users member runs one known-good binary instead of a personal
# install. Only `publish`, `activate` and `installer` write to $DEPLOY_ROOT, and
# each is default-refusing (see scripts/publish-claude-binary.sh).

# Add shared uv/bin to PATH (curl, jq, sha256sum, getfacl come from the system)
export PATH="/sdf/group/lcls/ds/dm/apps/dev/bin:$PATH"

export CLAUDE_BINARY_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The tree being WRITTEN TO. Read-only in every mode but publish/activate/installer.
export DEPLOY_ROOT="${DEPLOY_ROOT:-/sdf/group/lcls/ds/dm/apps/dev}"

# The Claude Code harness tree and the binary root inside it. Deliberately
# inside claude/ rather than beside uv in dev/bin/: claude/ is mode 2750
# ps-users, which is the same audience as dev/env/slac-key.dat and the deployed
# skills. dev/bin/ is 2775 with other r-x, so publishing there would hand the
# binary to every S3DF user while the key it needs stays ps-users-only.
export CLAUDE_TREE_ROOT="${CLAUDE_TREE_ROOT:-$DEPLOY_ROOT/claude}"
export CLAUDE_BIN_ROOT="${CLAUDE_BIN_ROOT:-$CLAUDE_TREE_ROOT/bin}"

# The version published by default. Pinned rather than tracking `stable` or
# `latest`: a bump is a deliberate act with its own verification round, not a
# side effect of running this tool on a different day.
export CLAUDE_BINARY_PIN="${CLAUDE_BINARY_PIN:-2.1.235}"

# Platform key in Anthropic's release manifest. S3DF is RHEL 8.10 x86-64 with
# glibc 2.28; the binary needs only libc/libm/libpthread/libdl/librt, so the
# glibc build (not -musl) is correct here.
export CLAUDE_BINARY_PLATFORM="${CLAUDE_BINARY_PLATFORM:-linux-x64}"

# Anthropic's release endpoint. <base>/<version>/manifest.json carries a
# SHA-256 and byte size per platform; <base>/<version>/<platform>/claude is the
# binary. <base>/stable and <base>/latest resolve channel names to versions.
export CLAUDE_BINARY_DOWNLOAD_BASE="${CLAUDE_BINARY_DOWNLOAD_BASE:-https://downloads.claude.ai/claude-code-releases}"

# Where downloads land before they are verified. Node-local /tmp on purpose:
# 18 GB free, and a 331 MB download has no business on the results tier, which
# was 97% full with 232 GB left when this was written. Nothing here is
# load-bearing after `publish` — it is a staging area, not an archive.
export CLAUDE_BINARY_STAGING="${CLAUDE_BINARY_STAGING:-/tmp/claude-binary-staging-$USER}"

# Group for everything published. ps-users, matching the skills tree and both
# gateway keys. See docs/deploy-permissions.md for why this is not ps-data.
export CLAUDE_BINARY_GROUP="${CLAUDE_BINARY_GROUP:-ps-users}"

# The deploy-opencode source checkout carrying claude/install-claude-lcls.sh.
# `installer` mode publishes that script so it stops being a hand-copy.
export CLAUDE_BINARY_SRC_REPO="${CLAUDE_BINARY_SRC_REPO:-/sdf/data/lcls/ds/prj/prjdat21/results/cwang31/deploy-opencode}"

# Refuse to accept a download outside this size band. A Claude Code release is
# ~330 MB; an HTML error page or a truncated transfer is not. The SHA-256 check
# catches these too, but a size gate fails earlier and more legibly.
export CLAUDE_BINARY_MIN_BYTES="${CLAUDE_BINARY_MIN_BYTES:-104857600}"
export CLAUDE_BINARY_MAX_BYTES="${CLAUDE_BINARY_MAX_BYTES:-1073741824}"

if [[ -f "$CLAUDE_BINARY_APP_DIR/env.local" ]]; then
    source "$CLAUDE_BINARY_APP_DIR/env.local"
fi
