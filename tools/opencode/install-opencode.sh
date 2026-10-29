#!/usr/bin/env bash
# Install an opencode release (https://github.com/anomalyco/opencode) into the shared dev tree.
#
#   $DEPLOY_ROOT/opencode-cli/<ver>/bin/opencode   the binary, alone in its bin/
#   $DEPLOY_ROOT/opencode-cli/<ver>/PROVENANCE     where it came from, how it was checked
#   $DEPLOY_ROOT/opencode-cli/current -> <ver>     the version opencode-sandbox runs
#
# (Not dev/opencode/: that is the shared CONFIG dir, OPENCODE_CONFIG_DIR.)
# opencode-sandbox runs current/bin/opencode and puts that bin/ on PATH inside
# the sandbox; docs/setup.md's opencode() wrapper uses the same directory. There
# is no dev/bin link.
#
# Installing does NOT switch anyone over. Try a new version first with
#   OPENCODE_SANDBOX_VERSION=<ver> opencode-sandbox
# then switch everyone with --activate. See CLAUDE.md ("Shared opencode binary")
# for the checks to run in between.
#
# Usage:
#   tools/opencode/install-opencode.sh <version>             # e.g. 1.19.5: download, verify, install
#   DRY_RUN=1 tools/opencode/install-opencode.sh <version>   # download + verify only, write nothing
#   tools/opencode/install-opencode.sh --activate <version>  # repoint current (upgrade or rollback)
#
# Verification, before anything is written:
#   1. sha256 of the archive must equal the digest GitHub's release API reports
#      for that asset.
#   2. `gh release verify-asset` checks GitHub's signed release attestation,
#      which lists the sha256 of every asset in the release. Run by
#      GH_ATTEST_BIN: default the shared $DEPLOY_ROOT/bin/gh, else gh on PATH.
#      (`gh attestation verify` does not apply: opencode publishes no build
#      provenance, only the release attestation.) Any failure = abort. Releases
#      older than GitHub's release attestations (1.2.10 is one) have none: verify
#      elsewhere and set OPENCODE_ATTEST=skip OPENCODE_ATTEST_NOTE="<how>", which
#      is recorded in PROVENANCE. Check 1 still runs.
#   3. The extracted binary must report version <ver> (which also proves it
#      runs on this node's glibc). It runs with a throwaway HOME, so the check
#      leaves nothing in yours.
#
# The binary cannot update itself from here: opencode's `upgrade` only knows
# installs whose path contains .opencode/bin or .local/bin. opencode-sandbox
# also sets OPENCODE_DISABLE_AUTOUPDATE=1, which hides the "/update to upgrade
# to OpenCode 2" prompt.
#
# Refuses to overwrite an existing <ver> directory. Old versions are kept for
# rollback; remove them by hand.
#
# Permissions follow dev/gh and dev/hunk: owner = you, group ps-users,
# directories 2755, files a+r with no group/other write, no ACLs.

set -euo pipefail

DEPLOY_ROOT="${DEPLOY_ROOT:-/sdf/group/lcls/ds/dm/apps/dev}"
GROUP="${PS_USERS_GROUP:-ps-users}"
DRY_RUN="${DRY_RUN:-0}"
REPO="anomalyco/opencode"
ASSET="opencode-linux-x64.tar.gz"
OC_HOME="$DEPLOY_ROOT/opencode-cli"

usage() { sed -n '2,47p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }

ACTIVATE_ONLY=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --activate) ACTIVATE_ONLY=1; shift ;;
esac
[ $# -eq 1 ] || { usage >&2; exit 1; }
VER="${1#v}"
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.19.5 (got '$1')"
DEST="$OC_HOME/$VER"

make_shared_dir() {
  [ -d "$1" ] && return 0
  mkdir "$1"
  setfacl -b "$1" 2>/dev/null || true
  chgrp "$GROUP" "$1"
  chmod 2755 "$1"   # after chgrp: chgrp clears setgid
}

# Run a binary with a throwaway HOME and XDG dirs, so a version check writes
# nothing into the invoking user's real ~/.local/share/opencode and friends.
run_isolated() {
  local h
  h="$(mktemp -d "${TMPDIR:-/tmp}/install-opencode-home-$USER-XXXXXX")"
  HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_DATA_HOME="$h/.local/share" \
    XDG_CACHE_HOME="$h/.cache" XDG_STATE_HOME="$h/.local/state" \
    OPENCODE_DISABLE_AUTOUPDATE=1 "$@" | sed -n 1p
  local rc=${PIPESTATUS[0]}
  rm -rf "$h"
  return "$rc"
}

# activate: point current at $VER (atomic rename). opencode-sandbox picks it up
# on its next launch; running sessions keep the version they started with.
activate() {
  [ -x "$DEST/bin/opencode" ] || die "$DEST/bin/opencode not found; install $VER first"
  local prev="(none)"
  [ -L "$OC_HOME/current" ] && prev="$(readlink "$OC_HOME/current")"
  if [ "$DRY_RUN" = "1" ]; then
    echo "(dry-run) would point $OC_HOME/current -> $VER (now: $prev)"
    return 0
  fi
  ln -sfn "$VER" "$OC_HOME/.current.new"
  mv -T "$OC_HOME/.current.new" "$OC_HOME/current"
  echo "✓ $OC_HOME/current -> $VER (was: $prev)"
  echo "✓ current/bin/opencode --version: $(run_isolated "$OC_HOME/current/bin/opencode" --version)"
}

if [ "$ACTIVATE_ONLY" = "1" ]; then
  activate
  exit 0
fi

[ -e "$DEST" ] && die "$DEST already exists; use --activate $VER to switch to it"
for c in curl sha256sum tar; do
  command -v "$c" >/dev/null || die "$c not on PATH"
done
GH="${GH_ATTEST_BIN:-}"
if [ -z "$GH" ]; then
  if [ -x "$DEPLOY_ROOT/bin/gh" ]; then GH="$DEPLOY_ROOT/bin/gh"; else GH="$(command -v gh || true)"; fi
fi
[ -n "$GH" ] || die "no gh to read the release digest and check its attestation; set GH_ATTEST_BIN"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/install-opencode-$USER-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

echo "── opencode $VER"
curl -fsSL -o "$WORK/$ASSET" "https://github.com/$REPO/releases/download/v$VER/$ASSET"

# 1. checksum against the digest GitHub records for the asset
EXPECTED="$("$GH" api "repos/$REPO/releases/tags/v$VER" \
  --jq ".assets[] | select(.name == \"$ASSET\") | .digest" | sed 's/^sha256://')"
[[ "$EXPECTED" =~ ^[0-9a-f]{64}$ ]] || die "no sha256 digest for $ASSET in release v$VER (got '$EXPECTED')"
ACTUAL="$(sha256sum "$WORK/$ASSET" | awk '{ print $1 }')"
[ "$EXPECTED" = "$ACTUAL" ] || die "sha256 mismatch for $ASSET: GitHub says $EXPECTED, got $ACTUAL"
echo "✓ sha256 $ACTUAL matches the release's asset digest"

# 2. signed release attestation (fail-closed: verified, or skipped with a recorded reason)
if [ "${OPENCODE_ATTEST:-verify}" = "skip" ]; then
  [ -n "${OPENCODE_ATTEST_NOTE:-}" ] || die "OPENCODE_ATTEST=skip needs OPENCODE_ATTEST_NOTE saying how $ASSET was verified instead"
  ATTEST="not run here (OPENCODE_ATTEST=skip): $OPENCODE_ATTEST_NOTE"
  echo "! attestation $ATTEST"
else
  if "$GH" release verify-asset "v$VER" "$WORK/$ASSET" --repo "$REPO" >"$WORK/attest.log" 2>&1; then
    ATTEST="verified with $GH ($("$GH" --version | sed -n 1p)): gh release verify-asset v$VER $ASSET --repo $REPO"
    echo "✓ release attestation verified with $GH"
  else
    sed -n 1,20p "$WORK/attest.log" >&2
    die "gh release verify-asset failed for $ASSET using $GH"
  fi
fi

# 3. extract + version check. The archive holds a single top-level `opencode`.
mkdir "$WORK/x"
tar -xzf "$WORK/$ASSET" -C "$WORK/x"
[ -f "$WORK/x/opencode" ] || die "$ASSET has no opencode binary at its top level"
chmod 0755 "$WORK/x/opencode"
GOT="$(run_isolated "$WORK/x/opencode" --version)"
[ "${GOT#v}" = "$VER" ] || die "extracted binary reports '$GOT', not $VER"
BIN_SHA="$(sha256sum "$WORK/x/opencode" | awk '{ print $1 }')"
echo "✓ binary runs here and reports $VER (binary sha256 $BIN_SHA)"

if [ "$DRY_RUN" = "1" ]; then
  echo "(dry-run) would install to $DEST; current would stay as it is"
  exit 0
fi

# install
make_shared_dir "$OC_HOME"
mkdir -p "$WORK/stage/bin"
mv "$WORK/x/opencode" "$WORK/stage/bin/opencode"
cp -r "$WORK/stage" "$DEST"
cat > "$DEST/PROVENANCE" <<EOF
opencode $VER
source:      https://github.com/$REPO/releases/tag/v$VER
asset:       $ASSET
sha256:      $ACTUAL (matches the asset digest in GitHub's release API)
binary:      bin/opencode sha256 $BIN_SHA
attestation: $ATTEST
installed:   $(date -u +%Y-%m-%dT%H:%M:%SZ) by $USER on $(hostname -s)
via:         tools/opencode/install-opencode.sh from deploy-opencode $(git -C "$(dirname "$0")" rev-parse --short HEAD 2>/dev/null || echo "(unknown commit)")
EOF
setfacl -R -b "$DEST" 2>/dev/null || true
chgrp -R "$GROUP" "$DEST"
chmod -R u+rwX,go+rX,go-w "$DEST"
find "$DEST" -type d -exec chmod 2755 {} +
echo "✓ installed $DEST"

if [ -L "$OC_HOME/current" ]; then
  echo "current is still $(readlink "$OC_HOME/current"). To try $VER first:"
  echo "  OPENCODE_SANDBOX_VERSION=$VER opencode-sandbox"
  echo "then switch everyone with:  $0 --activate $VER"
else
  echo "no current yet; activate with:  $0 --activate $VER"
fi
