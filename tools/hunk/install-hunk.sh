#!/usr/bin/env bash
# Install a hunk release (https://github.com/modem-dev/hunk) into the shared dev tree.
#
#   $DEPLOY_ROOT/hunk/<ver>/      bin/hunk, skills/, metadata.json + PROVENANCE
#   $DEPLOY_ROOT/hunk/current     -> <ver>
#   $DEPLOY_ROOT/hunk/bin/hunk    wrapper (copied from tools/hunk/hunk-wrapper.sh)
#   $DEPLOY_ROOT/bin/hunk         -> ../hunk/bin/hunk
#
# $DEPLOY_ROOT/bin is FIRST on PATH in every claude-lcls agent shell and on PATH
# inside opencode-sandbox, so the agent side needs no installer re-run. Users
# open the viewer in their own terminal with the absolute path:
#   /sdf/group/lcls/ds/dm/apps/dev/bin/hunk diff
# The wrapper gives each user their own session port; read its header.
# The hunk binary finds its bundled skills by walking up from its own path,
# so <ver>/skills sits beside <ver>/bin as in the release archive.
#
# Usage:
#   tools/hunk/install-hunk.sh <version>             # e.g. 0.24.1: install, then activate
#   DRY_RUN=1 tools/hunk/install-hunk.sh <version>   # download + verify only, write nothing
#   tools/hunk/install-hunk.sh --activate <version>  # repoint current (upgrade or rollback)
#                                                    # and refresh the wrapper
#
# Verification, before anything is written:
#   1. sha256 of the archive must match SHA256SUMS from the same release.
#   2. `gh attestation verify --repo modem-dev/hunk` checks GitHub's signed
#      build provenance, run by GH_ATTEST_BIN: default the shared
#      $DEPLOY_ROOT/bin/gh, else gh on PATH. Any failure = abort. To skip,
#      verify elsewhere and set HUNK_ATTEST=skip HUNK_ATTEST_NOTE="<how>",
#      which is recorded in PROVENANCE.
#   3. The extracted binary must report version <ver> (which also proves it
#      runs on this node's glibc).
#
# Keep the hunk-review skill in step: its skills.manifest.json ref should be the
# commit of tag v<ver>. After installing, this script compares the bundled
# SKILL.md with the deployed one and warns if they differ.
#
# Refuses to overwrite an existing <ver> directory. Old versions are kept for
# rollback; remove them by hand.
#
# Permissions follow dev/gh: owner = you, group ps-users, directories 2755,
# files a+r with no group/other write, no ACLs.

set -euo pipefail

DEPLOY_ROOT="${DEPLOY_ROOT:-/sdf/group/lcls/ds/dm/apps/dev}"
GROUP="${PS_USERS_GROUP:-ps-users}"
DRY_RUN="${DRY_RUN:-0}"
ASSET="hunkdiff-linux-x64.tar.gz"
HUNK_HOME="$DEPLOY_ROOT/hunk"
WRAPPER_SRC="$(dirname "$(readlink -f "$0")")/hunk-wrapper.sh"
WRAPPER="$HUNK_HOME/bin/hunk"
BIN_LINK="$DEPLOY_ROOT/bin/hunk"
LINK_TARGET="../hunk/bin/hunk"
DEPLOYED_SKILL="$DEPLOY_ROOT/claude/skills/hunk-review/SKILL.md"

usage() { sed -n '2,41p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }

ACTIVATE_ONLY=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --activate) ACTIVATE_ONLY=1; shift ;;
esac
[ $# -eq 1 ] || { usage >&2; exit 1; }
VER="${1#v}"
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 0.24.1 (got '$1')"
DEST="$HUNK_HOME/$VER"
[ -f "$WRAPPER_SRC" ] || die "wrapper source $WRAPPER_SRC not found"

make_shared_dir() {
  [ -d "$1" ] && return 0
  mkdir "$1"
  setfacl -b "$1" 2>/dev/null || true
  chgrp "$GROUP" "$1"
  chmod 2755 "$1"   # after chgrp: chgrp clears setgid
}

# Copy the wrapper in when it is missing or differs (temp file + rename, so a
# running `hunk` never sees a half-written script).
install_wrapper() {
  if [ -f "$WRAPPER" ] && cmp -s "$WRAPPER_SRC" "$WRAPPER"; then
    echo "✓ $WRAPPER is current"
    return 0
  fi
  make_shared_dir "$HUNK_HOME/bin"
  cp "$WRAPPER_SRC" "$HUNK_HOME/bin/.hunk.new"
  setfacl -b "$HUNK_HOME/bin/.hunk.new" 2>/dev/null || true
  chgrp "$GROUP" "$HUNK_HOME/bin/.hunk.new"
  chmod 0755 "$HUNK_HOME/bin/.hunk.new"
  mv -T "$HUNK_HOME/bin/.hunk.new" "$WRAPPER"
  echo "✓ wrapper installed at $WRAPPER"
}

# Warn when the deployed hunk-review skill is not the one this release bundles.
check_skill() {
  local bundled="$HUNK_HOME/$VER/skills/hunk-review/SKILL.md"
  [ -f "$bundled" ] || return 0
  if [ ! -f "$DEPLOYED_SKILL" ]; then
    echo "! hunk-review is not deployed yet ($DEPLOYED_SKILL); deploy it with ./deploy.sh"
    return 0
  fi
  # Compare bodies only: render.sh rewrites the frontmatter.
  body() { awk 'n >= 2 { print } /^---$/ && n < 2 { n++ }' "$1"; }
  if [ "$(body "$bundled")" = "$(body "$DEPLOYED_SKILL")" ]; then
    echo "✓ deployed hunk-review skill matches the one bundled with $VER"
  else
    echo "! deployed hunk-review skill differs from the one bundled with $VER:"
    echo "  set its skills.manifest.json ref to the commit of tag v$VER and redeploy"
  fi
}

# activate: point current at $VER (atomic rename), refresh the wrapper, then
# make sure the bin link exists. Never replaces a bin/hunk that is something
# other than our link.
activate() {
  [ -x "$DEST/bin/hunk" ] || die "$DEST/bin/hunk not found; install $VER first"
  if [ "$DRY_RUN" = "1" ]; then
    echo "(dry-run) would point $HUNK_HOME/current -> $VER, install $WRAPPER and link $BIN_LINK -> $LINK_TARGET"
    return 0
  fi
  ln -sfn "$VER" "$HUNK_HOME/.current.new"
  mv -T "$HUNK_HOME/.current.new" "$HUNK_HOME/current"
  echo "✓ $HUNK_HOME/current -> $VER"
  install_wrapper
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
  echo "✓ $BIN_LINK --version: $("$BIN_LINK" --version | sed -n 1p)"
  check_skill
}

if [ "$ACTIVATE_ONLY" = "1" ]; then
  activate
  exit 0
fi

[ -e "$DEST" ] && die "$DEST already exists; use --activate $VER to switch to it"
for c in curl sha256sum tar; do
  command -v "$c" >/dev/null || die "$c not on PATH"
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/install-hunk-$USER-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

BASE="https://github.com/modem-dev/hunk/releases/download/v$VER"

echo "── hunk $VER"
curl -fsSL -o "$WORK/$ASSET" "$BASE/$ASSET"
curl -fsSL -o "$WORK/SHA256SUMS" "$BASE/SHA256SUMS"

# 1. checksum
EXPECTED="$(awk -v f="$ASSET" '$2 == f { print $1 }' "$WORK/SHA256SUMS")"
[ -n "$EXPECTED" ] || die "$ASSET is not listed in SHA256SUMS"
ACTUAL="$(sha256sum "$WORK/$ASSET" | awk '{ print $1 }')"
[ "$EXPECTED" = "$ACTUAL" ] || die "sha256 mismatch for $ASSET: expected $EXPECTED, got $ACTUAL"
echo "✓ sha256 $ACTUAL matches SHA256SUMS"

# 2. build provenance (fail-closed: verified, or skipped with a recorded reason)
if [ "${HUNK_ATTEST:-verify}" = "skip" ]; then
  [ -n "${HUNK_ATTEST_NOTE:-}" ] || die "HUNK_ATTEST=skip needs HUNK_ATTEST_NOTE saying how $ASSET was verified instead"
  ATTEST="not run here (HUNK_ATTEST=skip): $HUNK_ATTEST_NOTE"
  echo "! attestation $ATTEST"
else
  VERIFIER="${GH_ATTEST_BIN:-}"
  if [ -z "$VERIFIER" ]; then
    if [ -x "$DEPLOY_ROOT/bin/gh" ]; then VERIFIER="$DEPLOY_ROOT/bin/gh"; else VERIFIER="$(command -v gh || true)"; fi
  fi
  [ -n "$VERIFIER" ] || die "no gh to run the attestation check; set GH_ATTEST_BIN, or see HUNK_ATTEST=skip above"
  if "$VERIFIER" attestation verify "$WORK/$ASSET" --repo modem-dev/hunk >"$WORK/attest.log" 2>&1; then
    ATTEST="verified with $VERIFIER ($("$VERIFIER" --version | sed -n 1p)): gh attestation verify --repo modem-dev/hunk"
    echo "✓ attestation verified with $VERIFIER"
  else
    sed -n 1,20p "$WORK/attest.log" >&2
    die "gh attestation verify failed for $ASSET using $VERIFIER"
  fi
fi

# 3. extract + version check. The archive holds one hunkdiff-linux-x64/ dir
# with hunk, metadata.json and skills/.
mkdir "$WORK/x"
tar -xzf "$WORK/$ASSET" -C "$WORK/x" --strip-components=1
[ -f "$WORK/x/hunk" ] || die "$ASSET has no hunk binary at its top level"
[ -d "$WORK/x/skills/hunk-review" ] || die "$ASSET has no skills/hunk-review"
chmod 0755 "$WORK/x/hunk"
# sed, not head: an early-exiting reader can SIGPIPE the binary under pipefail.
GOT="$(HUNK_DISABLE_UPDATE_NOTICE=1 "$WORK/x/hunk" --version | sed -n 1p)"
[ "${GOT#v}" = "$VER" ] || die "extracted binary reports '$GOT', not $VER"
echo "✓ binary runs here and reports $VER"

if [ "$DRY_RUN" = "1" ]; then
  echo "(dry-run) would install to $DEST, then point current at it, install the wrapper and link $BIN_LINK"
  exit 0
fi

# install
make_shared_dir "$HUNK_HOME"
mkdir -p "$WORK/stage/bin"
mv "$WORK/x/hunk" "$WORK/stage/bin/hunk"
mv "$WORK/x/skills" "$WORK/stage/skills"
[ -f "$WORK/x/metadata.json" ] && mv "$WORK/x/metadata.json" "$WORK/stage/metadata.json"
cp -r "$WORK/stage" "$DEST"
cat > "$DEST/PROVENANCE" <<EOF
hunk $VER
source:      https://github.com/modem-dev/hunk/releases/tag/v$VER
asset:       $ASSET
sha256:      $ACTUAL (matches SHA256SUMS from the same release)
attestation: $ATTEST
installed:   $(date -u +%Y-%m-%dT%H:%M:%SZ) by $USER on $(hostname -s)
via:         tools/hunk/install-hunk.sh from deploy-opencode $(git -C "$(dirname "$0")" rev-parse --short HEAD 2>/dev/null || echo "(unknown commit)")
EOF
setfacl -R -b "$DEST" 2>/dev/null || true
chgrp -R "$GROUP" "$DEST"
chmod -R u+rwX,go+rX,go-w "$DEST"
find "$DEST" -type d -exec chmod 2755 {} +
echo "✓ installed $DEST"

activate
