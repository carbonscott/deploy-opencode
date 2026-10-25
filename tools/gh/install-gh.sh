#!/usr/bin/env bash
# Install a GitHub CLI (gh) release into the shared dev tree.
#
#   $DEPLOY_ROOT/gh/<ver>/        the release's bin/gh, share/man, LICENSE + PROVENANCE
#   $DEPLOY_ROOT/gh/current       -> <ver>
#   $DEPLOY_ROOT/bin/gh           -> ../gh/current/bin/gh
#
# $DEPLOY_ROOT/bin is FIRST on PATH in every claude-lcls agent shell
# (SHARED_TOOLS_BIN in claude/install-claude-lcls.sh) and on PATH inside
# opencode-sandbox, so this one link reaches both harnesses with no installer
# re-run. The gh-skills skill depends on it. Each user still logs in once, in
# their own terminal, with the absolute path:
#   /sdf/group/lcls/ds/dm/apps/dev/bin/gh auth login
#
# Usage:
#   tools/gh/install-gh.sh <version>             # e.g. 2.103.2: install, then activate
#   DRY_RUN=1 tools/gh/install-gh.sh <version>   # download + verify only, write nothing
#   tools/gh/install-gh.sh --activate <version>  # repoint current (upgrade or rollback)
#
# Verification, before anything is written:
#   1. sha256 of the tarball must match gh_<ver>_checksums.txt from the same
#      release. Mismatch = abort.
#   2. `gh attestation verify --repo cli/cli` checks GitHub's signed build
#      provenance, run by GH_ATTEST_BIN: default the shared $DEPLOY_ROOT/bin/gh
#      (so the installed version vouches for the next one), else gh on PATH.
#      Any failure = abort. A verifier too old for the current attestation
#      format crashes (gh 2.62.0 panics on 2.103.2); for that bootstrap case,
#      verify elsewhere and set GH_ATTEST=skip GH_ATTEST_NOTE="<how>", which is
#      recorded in PROVENANCE. Never use the new binary to vouch for itself.
#   3. The extracted binary must report `gh version <ver>`.
#
# Refuses to overwrite an existing <ver> directory. Old versions are kept for
# rollback; remove them by hand.
#
# Permissions follow dev/pass and dev/keyswitch: owner = you, group ps-users,
# directories 2755, files a+r with no group/other write, no ACLs. (dev/ carries
# default ACLs that would otherwise make new files group-writable.)

set -euo pipefail

DEPLOY_ROOT="${DEPLOY_ROOT:-/sdf/group/lcls/ds/dm/apps/dev}"
GROUP="${PS_USERS_GROUP:-ps-users}"
DRY_RUN="${DRY_RUN:-0}"
ARCH="linux_amd64"
GH_HOME="$DEPLOY_ROOT/gh"
BIN_LINK="$DEPLOY_ROOT/bin/gh"
LINK_TARGET="../gh/current/bin/gh"

usage() { sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }

ACTIVATE_ONLY=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --activate) ACTIVATE_ONLY=1; shift ;;
esac
[ $# -eq 1 ] || { usage >&2; exit 1; }
VER="${1#v}"
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 2.103.2 (got '$1')"
DEST="$GH_HOME/$VER"

# activate: point current at $VER (atomic rename), then make sure the bin link
# exists. Never replaces a bin/gh that is something other than our link.
activate() {
  [ -x "$DEST/bin/gh" ] || die "$DEST/bin/gh not found; install $VER first"
  if [ "$DRY_RUN" = "1" ]; then
    echo "(dry-run) would point $GH_HOME/current -> $VER and link $BIN_LINK -> $LINK_TARGET"
    return 0
  fi
  ln -sfn "$VER" "$GH_HOME/.current.new"
  mv -T "$GH_HOME/.current.new" "$GH_HOME/current"
  echo "✓ $GH_HOME/current -> $VER"
  if [ -L "$BIN_LINK" ]; then
    [ "$(readlink "$BIN_LINK")" = "$LINK_TARGET" ] || \
      die "$BIN_LINK points to '$(readlink "$BIN_LINK")', not $LINK_TARGET; fix by hand"
    echo "✓ $BIN_LINK -> $LINK_TARGET (already in place)"
  elif [ -e "$BIN_LINK" ]; then
    die "$BIN_LINK exists and is not a symlink; refusing to replace it"
  else
    ln -s "$LINK_TARGET" "$BIN_LINK"
    echo "✓ $BIN_LINK -> $LINK_TARGET"
  fi
  "$BIN_LINK" --version | sed -n 1p
}

if [ "$ACTIVATE_ONLY" = "1" ]; then
  activate
  exit 0
fi

[ -e "$DEST" ] && die "$DEST already exists; use --activate $VER to switch to it"
for c in curl sha256sum tar; do
  command -v "$c" >/dev/null || die "$c not on PATH"
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/install-gh-$USER-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

BASE="https://github.com/cli/cli/releases/download/v$VER"
TARBALL="gh_${VER}_${ARCH}.tar.gz"
SUMS="gh_${VER}_checksums.txt"

echo "── gh $VER"
curl -fsSL -o "$WORK/$TARBALL" "$BASE/$TARBALL"
curl -fsSL -o "$WORK/$SUMS" "$BASE/$SUMS"

# 1. checksum
EXPECTED="$(awk -v f="$TARBALL" '$2 == f { print $1 }' "$WORK/$SUMS")"
[ -n "$EXPECTED" ] || die "$TARBALL is not listed in $SUMS"
ACTUAL="$(sha256sum "$WORK/$TARBALL" | awk '{ print $1 }')"
[ "$EXPECTED" = "$ACTUAL" ] || die "sha256 mismatch for $TARBALL: expected $EXPECTED, got $ACTUAL"
echo "✓ sha256 $ACTUAL matches $SUMS"

# 2. build provenance (fail-closed: verified, or skipped with a recorded reason)
if [ "${GH_ATTEST:-verify}" = "skip" ]; then
  [ -n "${GH_ATTEST_NOTE:-}" ] || die "GH_ATTEST=skip needs GH_ATTEST_NOTE saying how $TARBALL was verified instead"
  ATTEST="not run here (GH_ATTEST=skip): $GH_ATTEST_NOTE"
  echo "! attestation $ATTEST"
else
  VERIFIER="${GH_ATTEST_BIN:-}"
  if [ -z "$VERIFIER" ]; then
    if [ -x "$BIN_LINK" ]; then VERIFIER="$BIN_LINK"; else VERIFIER="$(command -v gh || true)"; fi
  fi
  [ -n "$VERIFIER" ] || die "no gh to run the attestation check; set GH_ATTEST_BIN, or see GH_ATTEST=skip above"
  if "$VERIFIER" attestation verify "$WORK/$TARBALL" --repo cli/cli >"$WORK/attest.log" 2>&1; then
    ATTEST="verified with $VERIFIER ($("$VERIFIER" --version | sed -n 1p)): gh attestation verify --repo cli/cli"
    echo "✓ attestation verified with $VERIFIER"
  else
    sed -n 1,20p "$WORK/attest.log" >&2
    die "gh attestation verify failed for $TARBALL using $VERIFIER. If that gh is too old (it may crash), set GH_ATTEST_BIN to a newer one, or verify elsewhere and use GH_ATTEST=skip GH_ATTEST_NOTE=..."
  fi
fi

# 3. extract + version check
tar -xzf "$WORK/$TARBALL" -C "$WORK"
SRC="$WORK/gh_${VER}_${ARCH}"
[ -x "$SRC/bin/gh" ] || die "tarball has no gh_${VER}_${ARCH}/bin/gh"
# sed, not head/grep -q: an early-exiting reader can SIGPIPE gh, and pipefail
# would turn that into a false failure.
case "$("$SRC/bin/gh" --version | sed -n 1p)" in
  "gh version $VER "*) ;;
  *) die "extracted binary does not report gh version $VER" ;;
esac
echo "✓ binary reports gh version $VER"

if [ "$DRY_RUN" = "1" ]; then
  echo "(dry-run) would install to $DEST, then point current at it and link $BIN_LINK"
  exit 0
fi

# install
if [ ! -d "$GH_HOME" ]; then
  mkdir "$GH_HOME"
  setfacl -b "$GH_HOME" 2>/dev/null || true
  chgrp "$GROUP" "$GH_HOME"
  chmod 2755 "$GH_HOME"   # after chgrp: chgrp clears setgid
fi
cp -r "$SRC" "$DEST"
cat > "$DEST/PROVENANCE" <<EOF
gh $VER
source:      https://github.com/cli/cli/releases/tag/v$VER
asset:       $TARBALL
sha256:      $ACTUAL (matches $SUMS from the same release)
attestation: $ATTEST
installed:   $(date -u +%Y-%m-%dT%H:%M:%SZ) by $USER on $(hostname -s)
via:         tools/gh/install-gh.sh from deploy-opencode $(git -C "$(dirname "$0")" rev-parse --short HEAD 2>/dev/null || echo "(unknown commit)")
EOF
setfacl -R -b "$DEST" 2>/dev/null || true
chgrp -R "$GROUP" "$DEST"
chmod -R u+rwX,go+rX,go-w "$DEST"
find "$DEST" -type d -exec chmod 2755 {} +
echo "✓ installed $DEST"

activate
