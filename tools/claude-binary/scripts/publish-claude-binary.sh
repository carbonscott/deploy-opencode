#!/bin/bash
#
# publish-claude-binary.sh — publish a pinned Claude Code binary into the live
# deployment so every ps-users member runs one known-good copy.
#
# Before this existed, install-claude-lcls.sh required a personal Claude Code
# install and refused to run without one. That left 17 deployed skills reachable
# only by people who had already installed the harness themselves, and it made
# claude-lcls hostage to the ~/.local/bin/claude launcher shim, which has been
# observed vanishing from a home directory mid-campaign.
#
# What gets published (see `plan`):
#   claude/bin/versions/<ver>   the binary, mode 0755, group ps-users
#   claude/bin/current          symlink -> versions/<ver>; the rollback pivot
#   claude/bin/VERSIONS.json    what is published, its SHA-256, when, by whom
#   claude/install-claude-lcls.sh   (`installer` mode only)
#
# Provenance is never assumed. Every binary is checked against the SHA-256 in
# Anthropic's own release manifest before it is published, and again after it
# lands. A binary that fails either check is deleted, not published.
#
# Usage:
#   ./publish-claude-binary.sh plan [<ver>]      Print every path that would change
#   ./publish-claude-binary.sh fetch [<ver>]     Download to staging + verify SHA-256
#   ./publish-claude-binary.sh list              Show what is published now
#   ./publish-claude-binary.sh verify            Check published state, end to end
#   ./publish-claude-binary.sh publish [<ver>] --yes-really-publish
#   ./publish-claude-binary.sh activate [<ver>] --yes-really-publish
#   ./publish-claude-binary.sh installer --yes-really-publish
#
# The three writing modes refuse by default. They print their full plan before
# touching anything, and writing into the real deployment additionally requires
# CLAUDE_BINARY_ALLOW_PROD=1 in the environment — the same two-gate shape as
# deploy-backup.sh's `restore`.
#
# Exit codes: 0 ok; 1 a check failed or a write was refused; 2 usage or setup error.
#
# See docs/claude-binary-publish.md in deploy-opencode.

set -euo pipefail
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/env.sh"

PROD_PREFIX="/sdf/group/lcls/ds/dm/apps"
VERSIONS_DIR="$CLAUDE_BIN_ROOT/versions"
CURRENT_LINK="$CLAUDE_BIN_ROOT/current"
VERSIONS_JSON="$CLAUDE_BIN_ROOT/VERSIONS.json"
INSTALLER_SRC="$CLAUDE_BINARY_SRC_REPO/claude/install-claude-lcls.sh"
# What a published installer SHOULD equal is what this ref holds, not whatever
# happens to be checked out in the source repo. See cmd_verify.
INSTALLER_REF="${INSTALLER_REF:-origin/main}"
INSTALLER_DST="$CLAUDE_TREE_ROOT/install-claude-lcls.sh"

log()  { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"; }
die()  { echo "ERROR: $*" >&2; exit 2; }
fail() { echo "FAIL: $*" >&2; }

# --help prints the header comment block. The range is DERIVED — consecutive
# comment lines from line 2 until the first line that is not one — rather than
# hardcoded as `sed -n '2,NNp'`. A hardcoded range silently truncates its own
# help the first time someone adds a line to the header, which is exactly the
# defect this script's sibling install-claude-lcls.sh carries.
usage() {
    awk 'NR==1 {next}
         /^#/  {sub(/^# ?/, ""); print; next}
               {exit}' "$0"
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found in PATH"; }
need curl; need jq; need sha256sum; need install

# ── Version resolution ────────────────────────────────────────────────────
# A bare version string is used as-is. "stable" and "latest" are resolved
# through Anthropic's channel endpoints and the RESULT is printed, so what got
# published is always a concrete version in the record rather than a moving name.
resolve_version() {
    local v="${1:-$CLAUDE_BINARY_PIN}"
    case "$v" in
        stable|latest)
            local resolved
            resolved="$(curl -fsSL --max-time 30 "$CLAUDE_BINARY_DOWNLOAD_BASE/$v" 2>/dev/null)" \
                || die "cannot resolve channel '$v' from $CLAUDE_BINARY_DOWNLOAD_BASE"
            [[ "$resolved" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
                || die "channel '$v' returned something that is not a version: $resolved"
            echo "$resolved"
            ;;
        *)
            [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
                || die "not a version: $v (expected N.N.N, 'stable' or 'latest')"
            echo "$v"
            ;;
    esac
}

# Sets MF_SUM / MF_SIZE for $1 on $CLAUDE_BINARY_PLATFORM from Anthropic's
# manifest. This is the only source of truth for what a release should contain;
# nothing downstream trusts a local file's own say-so.
#
# Globals rather than stdout on purpose. As a `$(...)` substitution, a `die` in
# here would exit only the SUBSHELL — the caller would carry on with an empty
# checksum and publish an unverified binary. Running in the current shell makes
# the die real.
MF_SUM=""
MF_SIZE=""
load_manifest() {
    local ver="$1" json
    json="$(curl -fsSL --max-time 60 "$CLAUDE_BINARY_DOWNLOAD_BASE/$ver/manifest.json" 2>/dev/null)" \
        || die "cannot fetch manifest for $ver"
    MF_SUM="$(jq -r --arg p "$CLAUDE_BINARY_PLATFORM" '.platforms[$p].checksum // empty' <<<"$json")"
    MF_SIZE="$(jq -r --arg p "$CLAUDE_BINARY_PLATFORM" '.platforms[$p].size // empty' <<<"$json")"
    [[ "$MF_SUM" =~ ^[a-f0-9]{64}$ ]] \
        || die "manifest for $ver has no usable checksum for $CLAUDE_BINARY_PLATFORM"
    [[ "$MF_SIZE" =~ ^[1-9][0-9]*$ ]] \
        || die "manifest for $ver has no usable size for $CLAUDE_BINARY_PLATFORM"
}

# Sets MF_SUM / MF_SIZE from VERSIONS.json when the version is already recorded
# there, falling back to the network. Rollback must not need the internet: the
# day `current` has to be flipped back is exactly the day other things are
# already broken.
load_expected() {
    local ver="$1"
    if [[ -f "$VERSIONS_JSON" ]]; then
        MF_SUM="$(jq -r --arg v "$ver" '.published[]? | select(.version == $v) | .sha256' "$VERSIONS_JSON" 2>/dev/null || true)"
        MF_SIZE="$(jq -r --arg v "$ver" '.published[]? | select(.version == $v) | .size' "$VERSIONS_JSON" 2>/dev/null || true)"
        if [[ "$MF_SUM" =~ ^[a-f0-9]{64}$ && "$MF_SIZE" =~ ^[1-9][0-9]*$ ]]; then
            return 0
        fi
    fi
    load_manifest "$ver"
}

sha_of() { sha256sum "$1" | cut -d' ' -f1; }

# ── Write gating ──────────────────────────────────────────────────────────
# Two gates, deliberately. --yes-really-publish says "I meant to write"; the
# CLAUDE_BINARY_ALLOW_PROD env var says "I meant to write to PRODUCTION". A
# rehearsal against a mock DEPLOY_ROOT needs only the first, so the second can
# stay off in every context except the real thing.
CONFIRMED=0
require_write_gates() {
    local what="$1"
    if [[ "$CONFIRMED" != 1 ]]; then
        echo >&2
        echo "REFUSED: $what would write to $CLAUDE_TREE_ROOT" >&2
        echo "         Re-run with --yes-really-publish once the plan above is what you want." >&2
        exit 1
    fi
    if [[ "$CLAUDE_TREE_ROOT" == "$PROD_PREFIX"* && "${CLAUDE_BINARY_ALLOW_PROD:-0}" != 1 ]]; then
        echo >&2
        echo "REFUSED: $CLAUDE_TREE_ROOT is the live deployment." >&2
        echo "         Set CLAUDE_BINARY_ALLOW_PROD=1 as well, once you have rehearsed" >&2
        echo "         against a mock DEPLOY_ROOT and taken a deploy-backup." >&2
        exit 1
    fi
}

# ── Directory creation ────────────────────────────────────────────────────
# The order is load-bearing and is the recipe from docs/deploy-permissions.md §4:
# mkdir, then chgrp, then chmod LAST. `chgrp` clears the setgid bit, so a chmod
# that runs before it leaves the directory without setgid and the next file
# created there inherits the maintainer's primary group (gu) instead of
# ps-users. That is the 2026-02-12 incident class.
ensure_dir() {
    local d="$1" mode="$2"
    if [[ -d "$d" ]]; then return 0; fi
    mkdir -p "$d"
    chgrp "$CLAUDE_BINARY_GROUP" "$d" || fail "chgrp $CLAUDE_BINARY_GROUP failed on $d"
    chmod "$mode" "$d"                || fail "chmod $mode failed on $d"
    log "created $d (mode $mode, group $CLAUDE_BINARY_GROUP)"
}

# Publish one file by staging it in the DESTINATION directory and renaming into
# place. A plain `cp` over a live path leaves a window in which readers see a
# half-written binary; `mv` within one filesystem does not.
atomic_install() {
    local src="$1" dst="$2" mode="$3" tmp
    tmp="$(mktemp "$(dirname "$dst")/.publish.XXXXXX")"
    cat "$src" > "$tmp"
    chgrp "$CLAUDE_BINARY_GROUP" "$tmp" || fail "chgrp failed on $tmp"
    chmod "$mode" "$tmp"                || fail "chmod failed on $tmp"
    mv -f "$tmp" "$dst"
}

# ── Modes ─────────────────────────────────────────────────────────────────

cmd_plan() {
    local ver sum size staged
    ver="$(resolve_version "${1:-}")"
    load_manifest "$ver"; sum="$MF_SUM"; size="$MF_SIZE"
    staged="$CLAUDE_BINARY_STAGING/claude-$ver-$CLAUDE_BINARY_PLATFORM"

    echo "DEPLOY_ROOT:      $DEPLOY_ROOT"
    echo "claude tree:      $CLAUDE_TREE_ROOT"
    echo "binary root:      $CLAUDE_BIN_ROOT"
    echo "version:          $ver  (pin: $CLAUDE_BINARY_PIN)"
    echo "platform:         $CLAUDE_BINARY_PLATFORM"
    echo "official sha256:  $sum"
    echo "official size:    $size bytes"
    echo "staging:          $CLAUDE_BINARY_STAGING"
    echo "group:            $CLAUDE_BINARY_GROUP"
    echo
    echo "Paths this tool can write, and their state now:"
    printf '  %-52s %s\n' "$CLAUDE_BIN_ROOT/"          "$([[ -d $CLAUDE_BIN_ROOT ]] && echo exists || echo 'WOULD CREATE (2755)')"
    printf '  %-52s %s\n' "$VERSIONS_DIR/"             "$([[ -d $VERSIONS_DIR ]] && echo exists || echo 'WOULD CREATE (2755)')"
    printf '  %-52s %s\n' "$VERSIONS_DIR/$ver"         "$([[ -f $VERSIONS_DIR/$ver ]] && echo 'exists — would be REPLACED' || echo 'WOULD CREATE (0755)')"
    printf '  %-52s %s\n' "$CURRENT_LINK"              "$([[ -L $CURRENT_LINK ]] && echo "symlink -> $(readlink "$CURRENT_LINK") — would be REPOINTED" || echo 'WOULD CREATE')"
    printf '  %-52s %s\n' "$VERSIONS_JSON"             "$([[ -f $VERSIONS_JSON ]] && echo 'exists — would be REWRITTEN' || echo 'WOULD CREATE (0644)')"
    printf '  %-52s %s\n' "$INSTALLER_DST"             "$([[ -f $INSTALLER_DST ]] && echo 'exists — `installer` mode would REPLACE' || echo '`installer` mode WOULD CREATE (0755)')"
    echo
    printf '  %-52s %s\n' "staged binary" "$([[ -f $staged ]] && echo "$staged" || echo 'not fetched yet — run `fetch` first')"
    echo
    echo "Nothing outside $CLAUDE_TREE_ROOT is touched. This mode wrote nothing."
}

cmd_fetch() {
    local ver sum size staged actual avail
    ver="$(resolve_version "${1:-}")"
    load_manifest "$ver"; sum="$MF_SUM"; size="$MF_SIZE"
    staged="$CLAUDE_BINARY_STAGING/claude-$ver-$CLAUDE_BINARY_PLATFORM"

    mkdir -p "$CLAUDE_BINARY_STAGING"

    # Idempotent: a staged file that already matches is not re-downloaded.
    if [[ -f "$staged" ]] && [[ "$(sha_of "$staged")" == "$sum" ]]; then
        log "already staged and verified: $staged"
        echo "$staged"
        return 0
    fi

    avail="$(df -B1 --output=avail "$CLAUDE_BINARY_STAGING" | tail -1)"
    (( avail > size * 2 )) || die "not enough room in $CLAUDE_BINARY_STAGING ($avail bytes free, need > $((size * 2)))"

    log "downloading $ver ($CLAUDE_BINARY_PLATFORM, $size bytes)"
    curl -fsSL --max-time 900 -o "$staged.part" \
        "$CLAUDE_BINARY_DOWNLOAD_BASE/$ver/$CLAUDE_BINARY_PLATFORM/claude" \
        || { rm -f "$staged.part"; die "download failed for $ver"; }

    local got
    got="$(stat -c %s "$staged.part")"
    if (( got < CLAUDE_BINARY_MIN_BYTES || got > CLAUDE_BINARY_MAX_BYTES )); then
        rm -f "$staged.part"
        die "downloaded $got bytes, outside the sane band — not a release binary"
    fi
    if (( got != size )); then
        rm -f "$staged.part"
        die "downloaded $got bytes, manifest says $size"
    fi

    actual="$(sha_of "$staged.part")"
    if [[ "$actual" != "$sum" ]]; then
        rm -f "$staged.part"
        die "SHA-256 mismatch for $ver: got $actual, manifest says $sum"
    fi

    chmod 0755 "$staged.part"
    mv -f "$staged.part" "$staged"
    log "verified against Anthropic's manifest: $sum"
    log "staged: $staged"
    echo "$staged"
}

cmd_publish() {
    local ver sum size staged landed
    ver="$(resolve_version "${1:-}")"
    load_manifest "$ver"; sum="$MF_SUM"; size="$MF_SIZE"
    staged="$CLAUDE_BINARY_STAGING/claude-$ver-$CLAUDE_BINARY_PLATFORM"

    [[ -f "$staged" ]] || die "no staged binary for $ver — run: $0 fetch $ver"
    [[ "$(sha_of "$staged")" == "$sum" ]] \
        || die "staged binary for $ver no longer matches the manifest — re-run fetch"

    echo "Would publish:"
    echo "  $staged"
    echo "    -> $VERSIONS_DIR/$ver   (0755, $CLAUDE_BINARY_GROUP, sha256 $sum)"
    require_write_gates "publish"

    ensure_dir "$CLAUDE_TREE_ROOT" 2750
    ensure_dir "$CLAUDE_BIN_ROOT" 2755
    ensure_dir "$VERSIONS_DIR" 2755
    atomic_install "$staged" "$VERSIONS_DIR/$ver" 0755

    # Verify at the DESTINATION, not the source. A copy that silently truncated
    # on a full filesystem would otherwise be published and trusted.
    landed="$(sha_of "$VERSIONS_DIR/$ver")"
    [[ "$landed" == "$sum" ]] || die "published file does not match: got $landed, expected $sum"
    log "published $VERSIONS_DIR/$ver (verified $landed)"

    write_versions_json "$ver" "$sum" "$size"
}

cmd_activate() {
    local ver tmp reported
    ver="$(resolve_version "${1:-}")"
    [[ -f "$VERSIONS_DIR/$ver" ]] || die "$ver is not published — run: $0 publish $ver"

    echo "Would repoint:"
    echo "  $CURRENT_LINK"
    echo "    from: $([[ -L $CURRENT_LINK ]] && readlink "$CURRENT_LINK" || echo '(none)')"
    echo "      to: versions/$ver"
    require_write_gates "activate"

    # Relative target, so the tree can be rehearsed or relocated without the
    # link pointing back at production. Swapped via a temp name + rename so
    # readers never observe a missing `current`.
    tmp="$CLAUDE_BIN_ROOT/.current.$$"
    ln -sfn "versions/$ver" "$tmp"
    mv -fT "$tmp" "$CURRENT_LINK"
    chgrp -h "$CLAUDE_BINARY_GROUP" "$CURRENT_LINK" 2>/dev/null \
        || fail "chgrp -h failed on $CURRENT_LINK"
    log "activated: current -> versions/$ver"

    reported="$("$CURRENT_LINK" --version 2>&1 | head -1 | awk '{print $1}')"
    [[ "$reported" == "$ver" ]] \
        || die "current runs but reports '$reported', not '$ver'"
    log "current --version reports $reported"

    load_expected "$ver"
    write_versions_json "$ver" "$MF_SUM" "$MF_SIZE"
}

cmd_installer() {
    local before after
    [[ -f "$INSTALLER_SRC" ]] || die "installer not found: $INSTALLER_SRC"

    before="$([[ -f "$INSTALLER_DST" ]] && md5sum "$INSTALLER_DST" | cut -d' ' -f1 || echo '(absent)')"
    echo "Would publish the installer:"
    echo "  $INSTALLER_SRC"
    echo "    md5 $(md5sum "$INSTALLER_SRC" | cut -d' ' -f1)"
    echo "    -> $INSTALLER_DST   (0755, $CLAUDE_BINARY_GROUP)"
    echo "    live copy now: $before"
    require_write_gates "installer"

    ensure_dir "$CLAUDE_TREE_ROOT" 2750
    atomic_install "$INSTALLER_SRC" "$INSTALLER_DST" 0755
    after="$(md5sum "$INSTALLER_DST" | cut -d' ' -f1)"
    [[ "$after" == "$(md5sum "$INSTALLER_SRC" | cut -d' ' -f1)" ]] \
        || die "published installer does not match source"
    log "published $INSTALLER_DST (md5 $after)"
}

# VERSIONS.json records what is published and where it came from, so a later
# `verify` can check the tree against a claim made at publish time rather than
# only against the network — which is what makes verification work offline.
write_versions_json() {
    local ver="$1" sum="$2" size="$3" tmp active
    active="$([[ -L "$CURRENT_LINK" ]] && basename "$(readlink "$CURRENT_LINK")" || echo "")"

    local entries='[]'
    [[ -f "$VERSIONS_JSON" ]] && entries="$(jq -c '.published // []' "$VERSIONS_JSON" 2>/dev/null || echo '[]')"

    tmp="$(mktemp "$CLAUDE_BIN_ROOT/.versions.XXXXXX")"
    jq -n \
        --argjson prev "$entries" \
        --arg ver "$ver" --arg sum "$sum" --argjson size "$size" \
        --arg platform "$CLAUDE_BINARY_PLATFORM" \
        --arg at "$(date -Iseconds)" --arg by "$USER" --arg host "$(hostname)" \
        --arg active "$active" \
        '{
           active: (if $active == "" then null else $active end),
           platform: $platform,
           published: (
             ($prev | map(select(.version != $ver)))
             + [{version: $ver, sha256: $sum, size: $size,
                 published_at: $at, published_by: $by, published_on: $host}]
             | sort_by(.version)
           )
         }' > "$tmp"
    chgrp "$CLAUDE_BINARY_GROUP" "$tmp" || fail "chgrp failed on $tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$VERSIONS_JSON"
    log "recorded $ver in $VERSIONS_JSON (active: ${active:-none})"
}

cmd_list() {
    [[ -d "$CLAUDE_BIN_ROOT" ]] || { echo "nothing published: $CLAUDE_BIN_ROOT does not exist"; return 0; }
    echo "binary root: $CLAUDE_BIN_ROOT"
    echo
    if [[ -d "$VERSIONS_DIR" ]]; then
        echo "published versions:"
        local v act
        act="$([[ -L "$CURRENT_LINK" ]] && basename "$(readlink "$CURRENT_LINK")" || echo "")"
        for v in "$VERSIONS_DIR"/*; do
            [[ -f "$v" ]] || continue
            printf '  %-12s %12s bytes  %s\n' \
                "$(basename "$v")" "$(stat -c %s "$v")" \
                "$([[ "$(basename "$v")" == "$act" ]] && echo '<- current' || echo '')"
        done
    fi
    echo
    echo "current: $([[ -L "$CURRENT_LINK" ]] && readlink "$CURRENT_LINK" || echo '(not set)')"
    [[ -f "$VERSIONS_JSON" ]] && { echo; echo "VERSIONS.json:"; jq . "$VERSIONS_JSON"; }
    return 0
}

cmd_verify() {
    local rc=0 v d act sum recorded reported

    [[ -d "$CLAUDE_BIN_ROOT" ]] || { fail "$CLAUDE_BIN_ROOT does not exist"; return 1; }
    [[ -f "$VERSIONS_JSON" ]]   || { fail "$VERSIONS_JSON missing"; return 1; }
    jq -e . "$VERSIONS_JSON" >/dev/null 2>&1 || { fail "$VERSIONS_JSON does not parse"; return 1; }

    echo "── directory modes and group"
    for d in "$CLAUDE_BIN_ROOT" "$VERSIONS_DIR"; do
        printf '  %-52s %s %s\n' "$d" "$(stat -c %a "$d")" "$(stat -c %G "$d")"
        [[ "$(stat -c %G "$d")" == "$CLAUDE_BINARY_GROUP" ]] \
            || { fail "$d is group $(stat -c %G "$d"), expected $CLAUDE_BINARY_GROUP"; rc=1; }
    done

    echo "── published binaries vs VERSIONS.json"
    for v in "$VERSIONS_DIR"/*; do
        [[ -f "$v" ]] || continue
        local name; name="$(basename "$v")"
        recorded="$(jq -r --arg v "$name" '.published[] | select(.version == $v) | .sha256' "$VERSIONS_JSON")"
        sum="$(sha_of "$v")"
        if [[ -z "$recorded" ]]; then
            fail "$name is published but has no VERSIONS.json record"; rc=1
        elif [[ "$sum" != "$recorded" ]]; then
            fail "$name sha256 $sum does not match recorded $recorded"; rc=1
        else
            printf '  %-12s sha256 ok  mode %s  group %s\n' "$name" "$(stat -c %a "$v")" "$(stat -c %G "$v")"
        fi
        [[ -x "$v" ]] || { fail "$name is not executable"; rc=1; }
    done

    echo "── current symlink"
    if [[ ! -L "$CURRENT_LINK" ]]; then
        fail "$CURRENT_LINK is not a symlink"; rc=1
    else
        act="$(readlink "$CURRENT_LINK")"
        printf '  current -> %s\n' "$act"
        [[ "$act" == versions/* ]] || { fail "current points outside versions/: $act"; rc=1; }
        if [[ -e "$CURRENT_LINK" ]]; then
            reported="$("$CURRENT_LINK" --version 2>&1 | head -1 | awk '{print $1}')"
            printf '  current --version -> %s\n' "$reported"
            [[ "$reported" == "$(basename "$act")" ]] \
                || { fail "current reports $reported but points at $(basename "$act")"; rc=1; }
        else
            fail "current is dangling"; rc=1
        fi
    fi

    echo "── readability for $CLAUDE_BINARY_GROUP"
    if command -v getfacl >/dev/null 2>&1; then
        getfacl -p "$CLAUDE_BIN_ROOT" 2>/dev/null | sed -n '/^\(user\|group\|other\|mask\)/s/^/  /p'
    fi

    if [[ -f "$INSTALLER_DST" ]]; then
        echo "── installer"
        printf '  %-52s %s %s md5 %s\n' "$INSTALLER_DST" \
            "$(stat -c %a "$INSTALLER_DST")" "$(stat -c %G "$INSTALLER_DST")" \
            "$(md5sum "$INSTALLER_DST" | cut -d' ' -f1)"
        # Compare against $INSTALLER_REF, not against the working tree.
        # CLAUDE_BINARY_SRC_REPO is a SHARED checkout that more than one session
        # uses, so it frequently sits on a feature branch, and the file there is
        # then not what was published and not what anyone intends to publish.
        #
        # Observed 2026-08-28: verify reported "published installer differs"
        # purely because another session had a branch checked out there, while
        # the published copy was byte-identical to origin/main. The old message
        # named a path without saying it was reading a working tree, which is
        # what made the false alarm convincing.
        #
        # `cat-file -e` is the existence check; `show | md5sum` then streams the
        # blob, so no trailing-newline round trip through a shell variable. The
        # ref's short SHA is printed because a LOCAL origin/main can be stale,
        # and a stale comparison should be diagnosable rather than mysterious.
        local want_md5="" want_desc="" ref_sha=""
        if git -C "$CLAUDE_BINARY_SRC_REPO" cat-file -e "$INSTALLER_REF:claude/install-claude-lcls.sh" 2>/dev/null; then
            want_md5="$(git -C "$CLAUDE_BINARY_SRC_REPO" show "$INSTALLER_REF:claude/install-claude-lcls.sh" | md5sum | cut -d' ' -f1)"
            ref_sha="$(git -C "$CLAUDE_BINARY_SRC_REPO" rev-parse --short "$INSTALLER_REF" 2>/dev/null || echo '?')"
            want_desc="$INSTALLER_REF ($ref_sha)"
        elif [[ -f "$INSTALLER_SRC" ]]; then
            want_md5="$(md5sum "$INSTALLER_SRC" | cut -d' ' -f1)"
            want_desc="working tree $INSTALLER_SRC (could not read $INSTALLER_REF -- may be any branch)"
        fi
        if [[ -n "$want_md5" ]]; then
            echo "  compared against: $want_desc"
            [[ "$(md5sum "$INSTALLER_DST" | cut -d' ' -f1)" == "$want_md5" ]] \
                || { fail "published installer differs from $want_desc"; rc=1; }
        fi
    fi

    echo
    (( rc == 0 )) && log "verify: all checks passed" || log "verify: FAILURES above"
    return $rc
}

# ── Argument handling ─────────────────────────────────────────────────────
MODE="${1:-}"; shift || true
ARG=""
for a in "$@"; do
    case "$a" in
        --yes-really-publish) CONFIRMED=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) die "unknown flag: $a" ;;
        *) [[ -n "$ARG" ]] && die "unexpected argument: $a"; ARG="$a" ;;
    esac
done

case "$MODE" in
    plan)      cmd_plan "$ARG" ;;
    fetch)     cmd_fetch "$ARG" ;;
    publish)   cmd_publish "$ARG" ;;
    activate)  cmd_activate "$ARG" ;;
    installer) cmd_installer ;;
    list)      cmd_list ;;
    verify)    cmd_verify ;;
    -h|--help) usage ;;
    *)         usage; exit 2 ;;
esac
