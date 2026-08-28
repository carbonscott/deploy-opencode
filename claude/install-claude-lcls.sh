#!/usr/bin/env bash
# Install `claude-lcls` — Claude Code pointed at the SLAC AI Gateway.
#
# Gives you a `claude-lcls` command that runs Claude Code against
# https://ai-api.slac.stanford.edu using the shared team key and the shared
# team binary, WITHOUT touching your existing `claude` setup (personal
# subscription, API key, whatever you already have). The two live side by side:
#
#     claude        -> your own install and ~/.claude/, untouched
#     claude-lcls   -> shared binary, SLAC gateway, team key, ~/.claude-lcls/
#
# You do NOT need to install Claude Code first. The binary is deployed for
# ps-users at /sdf/group/lcls/ds/dm/apps/dev/claude/bin/current, and that is the
# only binary claude-lcls runs. A personal install, if you have one, is never
# read — not as a fallback, not at all.
#
# Everything claude-lcls writes stays in your own $HOME/.claude-lcls/: settings,
# sessions and transcripts included. Nothing is shared between users except the
# read-only binary and the read-only skills.
#
# Usage:
#   ./install-claude-lcls.sh              # install (safe to re-run)
#   ./install-claude-lcls.sh --uninstall  # remove it again
#   ./install-claude-lcls.sh --dry-run    # show what would happen, write nothing
#
# Requirements: membership in `ps-users` and the SLAC network or VPN. The script
# checks both — plus that the shared binary runs — before writing anything.
#
# See docs/claude-code-lcls-setup.md for the reference guide.

set -euo pipefail

# ─── Settings (override via env if you must) ──────────────────────────────
LCLS_DIR="${LCLS_DIR:-$HOME/.claude-lcls}"
KEY_FILE="${KEY_FILE:-/sdf/group/lcls/ds/dm/apps/dev/env/slac-key.dat}"
BASE_URL="${BASE_URL:-https://ai-api.slac.stanford.edu}"
FUNC_NAME="${FUNC_NAME:-claude-lcls}"
SKILLS_SRC="${SKILLS_SRC:-/sdf/group/lcls/ds/dm/apps/dev/claude/skills}"
DRY_RUN="${DRY_RUN:-0}"

# The shared team binary. A symlink into bin/versions/<ver>, so a version bump
# or a rollback is a symlink flip on the deploy side and needs no change here
# and no action from you. Never resolve this to a pinned version: the whole
# point is that the deployment decides which version everyone runs.
SHARED_BIN="${SHARED_BIN:-/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current}"

# Escape hatch, opt-in only. Set CLAUDE_LCLS_BIN to run claude-lcls against some
# other binary — testing this script, or pinning an older version during an
# incident. It is never consulted implicitly: leaving it unset does NOT fall
# back to a personal install.
CLAUDE_LCLS_BIN="${CLAUDE_LCLS_BIN:-}"

MARK_BEGIN="# >>> claude-lcls >>>"
MARK_END="# <<< claude-lcls <<<"

ok()   { echo "  ✓ $*"; }
warn() { echo "  WARN: $*" >&2; }
die()  { echo "  ✗ $*" >&2; exit 1; }
step() { echo; echo "── $*"; }

# --help prints the header comment block. The range is DERIVED — consecutive
# comment lines from line 2 until the first line that is not one — rather than
# hardcoded as `sed -n '2,20p'`. The hardcoded form silently truncated its own
# help the moment the header grew by a line, which is precisely what happened
# when the shared-binary paragraphs were added above.
usage() {
  awk 'NR==1 {next}
       /^#/  {sub(/^# ?/, ""); print; next}
             {exit}' "$0"
}

# Marker matching is normalised: trailing whitespace and carriage returns are
# stripped before comparing, so a CRLF rc or a marker line with a stray trailing
# space is still recognised. EVERY marker test below goes through one of these
# three helpers, so grep-style and awk-style matching can never drift apart.

# stdout = $1 with only COMPLETE marker blocks removed, PLUS the single blank
# line the install appends immediately before each block. The install writes
# `printf '\n%s\n' "$SNIPPET" >> "$rc"`, so every run adds one leading blank;
# a strip that removed only marker-to-marker lines left every one of them
# behind and ten installs + one --uninstall left ten blank lines where the
# original file had none. Blank lines are therefore buffered, and exactly one
# is dropped when it is directly adjacent to a begin marker.
#
# An UNTERMINATED block (begin marker, no end marker) is held back and
# re-emitted verbatim -- together with the blank line provisionally dropped in
# front of it -- so a hand-edited or half-written rc never loses anything.
strip_block() {
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    function flush(drop,   i, n) {
      have_dropped = 0; dropped = ""
      n = nb
      # Only a TRULY empty line can be the separator the install wrote with
      # printf "\n". A line of spaces or tabs belongs to the user and is never
      # consumed, even though the marker normalisation above calls it blank.
      if (drop && nb > 0 && pend[nb] == "") {
        dropped = pend[nb]; have_dropped = 1; n = nb - 1
      }
      for (i = 1; i <= n; i++) print pend[i]
      nb = 0
    }
    { line = $0; sub(/[ \t\r]+$/, "", line) }
    inblk && line == e  { inblk = 0; hold = "";      next }
    inblk               { hold = hold $0 ORS;        next }
    line == b           { flush(1); inblk = 1; hold = $0 ORS; next }
    line == ""          { pend[++nb] = $0;           next }
                        { flush(0); print }
    END                 {
                          if (inblk) {
                            if (have_dropped) print dropped
                            printf "%s", hold
                          } else {
                            flush(0)
                          }
                        }
  ' "$1"
}

# Exit 0 when $1 contains a begin marker at all.
# Exits non-zero for "no", so call it only as an `if`/`&&` condition.
has_block() {
  awk -v b="$MARK_BEGIN" '
    { line = $0; sub(/[ \t\r]+$/, "", line) }
    line == b { found = 1 }
    END       { exit (found ? 0 : 1) }
  ' "$1"
}

# Exit 0 when $1's markers are unbalanced, either shape:
#   * a begin marker with NO matching end marker — what strip_block refuses to
#     delete, so appending on top of it would build a 2-begin/1-end rc;
#   * a second begin marker INSIDE an open block — that 2-begin/1-end rc, which
#     an earlier version of this script could produce, and whose user lines
#     strip_block would swallow between the orphan begin and the first end.
# Same normalisation as strip_block, so the two can never disagree about what a
# marker is. Exits non-zero for "no", so call it only as an `if`/`&&` condition.
has_unterminated_block() {
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    { line = $0; sub(/[ \t\r]+$/, "", line) }
    line == b && !inblk { inblk = 1; next }
    line == b && inblk  { bad = 1;   next }
    inblk && line == e  { inblk = 0; next }
    END                 { exit ((inblk || bad) ? 0 : 1) }
  ' "$1"
}

# stdout = the physical file $1 refers to; exit 1 when a symlink cannot be
# resolved. `readlink -f` exits 1 and prints NOTHING when a non-final component
# of the chain is missing, or when the chain loops back on itself. Every caller
# has to notice that: an unchecked `target="$(readlink -f "$rc")"` leaves target
# empty, `dirname ""` is ".", and every later test then silently asks about the
# current directory instead of the rc -- so the same $HOME gives a different
# answer depending on where the user happened to cd first.
rc_target() {
  local rc="$1" t
  if [ -L "$rc" ]; then
    t="$(readlink -f "$rc" 2>/dev/null)" || return 1
    [ -n "$t" ] || return 1
    printf '%s\n' "$t"
  else
    printf '%s\n' "$rc"
  fi
}

# strip_block $1 back into place, PRESERVING mode, ownership AND symlink-ness.
# The GNU `sed -i` this replaced kept the mode; a fresh temp file + mv would
# silently widen a 600 rc to whatever the umask says -- hence the chmod.
#
# The symlink resolution matters just as much: a $HOME/.bashrc that is a
# symlink into a dotfiles repo is the common case for anyone using stow or
# chezmoi, and renaming a temp file over it REPLACES the link with a regular
# file. The dotfiles copy is then orphaned still holding a claude-lcls block
# that --uninstall can never reach, and the next `stow` puts that stale block
# straight back. The first install never showed this because it takes the
# append path (`>>` follows the link); only the SECOND run, which rewrites,
# broke the link. Resolve to the physical file and rename onto THAT instead,
# which keeps the rename atomic and leaves $HOME/.bashrc a symlink.
rewrite_stripped() {
  local rc="$1" target tmp
  target="$(rc_target "$rc")" || die "cannot resolve $rc to a real file: broken symlink chain, or a symlink loop."
  tmp="$target.tmp.$$"
  strip_block "$rc" > "$tmp"
  chmod --reference="$target" "$tmp" 2>/dev/null || chmod "$(stat -c %a "$target")" "$tmp"
  chown --reference="$target" "$tmp" 2>/dev/null || true
  mv "$tmp" "$target"
}

# rc files left untouched because their markers are broken; reported at the end.
SKIPPED_RCS=""

# Warn about, and record, an rc whose markers we refuse to edit.
skip_broken_rc() {
  local rc="$1"
  warn "$rc has an UNTERMINATED $FUNC_NAME block: a '$MARK_BEGIN' line with no matching '$MARK_END' (or a second '$MARK_BEGIN' inside an open block)."
  warn "left $rc COMPLETELY untouched — nothing stripped, nothing appended, no backup written."
  warn "fix it by hand (delete the stray '$MARK_BEGIN' line, or add the missing '$MARK_END') so exactly one begin/end pair remains, then re-run."
  SKIPPED_RCS="$SKIPPED_RCS $rc"
}

# rc files left untouched because we cannot write them; reported at the end.
UNWRITABLE_RCS=""

# Set to 1 as soon as the block lands in ANY rc. The end-of-section verdict
# turns on it: refusing one rc while successfully installing into another is a
# warning, not a failure, and must not abort before verification runs.
RC_INSTALLED=0

# Exit 0 when $1 can actually be updated by the operation about to run on it.
#
# Without this gate a mode-444 rc (or a $HOME/.bashrc that is a DIRECTORY)
# surfaced as a bare `install-claude-lcls.sh: line NNN: /path/.bashrc:
# Permission denied` from bash -- and only AFTER the config dir, settings.json
# and all 17 skill symlinks had already been written, bypassing every warn/skip
# path this script owns. Check first, and report it the way we report every
# other rc we refuse to touch.
#
# The two write paths need DIFFERENT permissions, and demanding both refuses rc
# files we can handle perfectly well:
#   * append (`>> "$rc"`) needs write on the FILE only. A read-only parent
#     directory is irrelevant, because no new name is ever created there.
#   * refresh (rewrite_stripped) renames a temp file into the file's directory,
#     so it needs write on the DIRECTORY too -- but it only ever runs when the
#     rc already carries a block.
# The directory is therefore required only when has_block says the refresh path
# is the one that will be taken.
rc_is_writable() {
  local rc="$1" target dir
  target="$(rc_target "$rc")" || return 1
  dir="$(dirname "$target")"
  # Exists but is not a regular file: a directory, a socket, a device.
  if [ -e "$target" ] && [ ! -f "$target" ]; then return 1; fi
  if [ ! -e "$target" ]; then
    # We would have to create it, so only its directory matters.
    [ -d "$dir" ] && [ -w "$dir" ]
    return
  fi
  [ -w "$target" ] || return 1
  if has_block "$rc"; then
    [ -w "$dir" ] || return 1
  fi
  return 0
}

# Warn about, and record, an rc we cannot write.
#
# The diagnosis has to name the thing that is ACTUALLY wrong. Reporting
# "not writable (mode 644)" for a perfectly writable file whose DIRECTORY is
# read-only contradicts itself in its own text, and the `chmod u+w` it suggests
# is a no-op that leaves the next run failing in exactly the same way.
#
# rc_target is called through `|| target=""` deliberately: it is ALLOWED to
# fail on a broken chain or a symlink loop, and this function runs as a plain
# statement rather than as a condition, so an unguarded command substitution
# would abort the whole script under `set -euo pipefail` -- printing nothing at
# all, which is the one outcome worse than the bare bash error this gate exists
# to replace.
skip_unwritable_rc() {
  local rc="$1" target dir
  target="$(rc_target "$rc")" || target=""
  if [ -z "$target" ]; then
    warn "$rc is a symlink that cannot be resolved: a missing directory somewhere in the chain, or a symlink loop."
    warn "inspect it with:  ls -l $rc   and   readlink -f $rc"
  else
    dir="$(dirname "$target")"
    if [ "$target" != "$rc" ]; then
      warn "$rc is a symlink to $target; everything below refers to the target."
    fi
    if [ -d "$target" ]; then
      warn "$target is a DIRECTORY, not a shell rc file."
      warn "move it aside (or point $rc at a real file), then re-run."
    elif [ -e "$target" ] && [ ! -f "$target" ]; then
      warn "$target exists but is not a regular file, so it is not a shell rc."
    elif [ -e "$target" ] && [ ! -w "$target" ]; then
      warn "$target is not writable (mode $(stat -c %a "$target" 2>/dev/null || echo '?'), owner $(stat -c %U "$target" 2>/dev/null || echo '?'))."
      warn "fix it with: chmod u+w $target   (then re-run this script)"
    else
      warn "$target is writable, but its directory $dir is not (mode $(stat -c %a "$dir" 2>/dev/null || echo '?'), owner $(stat -c %U "$dir" 2>/dev/null || echo '?'))."
      warn "refreshing an existing block renames a temp file into that directory, so it needs write permission on the DIRECTORY, not on the file."
      warn "fix it with: chmod u+w $dir   (then re-run this script)"
    fi
  fi
  warn "left $rc COMPLETELY untouched -- nothing stripped, nothing appended, no backup written."
  UNWRITABLE_RCS="$UNWRITABLE_RCS $rc"
}

MODE=install
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE=uninstall ;;
    --dry-run)   DRY_RUN=1 ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "unknown argument: $arg (try --help)" ;;
  esac
done

# DRY_RUN is compared against 1 in a dozen places below, so normalise it ONCE
# here — otherwise DRY_RUN=true would quietly perform a REAL install.
case "$(printf '%s' "$DRY_RUN" | tr 'A-Z' 'a-z')" in
  1|true|yes|y|on)     DRY_RUN=1 ;;
  0|false|no|n|off|'') DRY_RUN=0 ;;
  *)                   die "DRY_RUN must be 0 or 1 (got: $DRY_RUN)" ;;
esac

# ─── Which shell rc files to touch ────────────────────────────────────────
rc_files() {
  local -a rcs=()
  [ -f "$HOME/.bashrc" ] && rcs+=("$HOME/.bashrc")
  [ -f "$HOME/.zshrc" ]  && rcs+=("$HOME/.zshrc")
  # Nothing to append to? Create .bashrc rather than silently doing nothing.
  [ ${#rcs[@]} -eq 0 ] && rcs+=("$HOME/.bashrc")
  printf '%s\n' "${rcs[@]}"
}

# ─── Uninstall ────────────────────────────────────────────────────────────
if [ "$MODE" = uninstall ]; then
  step "Removing $FUNC_NAME"
  while IFS= read -r rc; do
    [ -f "$rc" ] || continue
    if ! rc_is_writable "$rc"; then
      skip_unwritable_rc "$rc"
      continue
    fi
    if has_unterminated_block "$rc"; then
      # Stripping here would be safe, but appending on the next INSTALL would
      # not: refuse uniformly so the user repairs the file once.
      skip_broken_rc "$rc"
      continue
    fi
    if has_block "$rc"; then
      if [ "$DRY_RUN" = 1 ]; then
        echo "  (dry-run) would strip the $FUNC_NAME block from $rc"
      else
        cp -p "$rc" "$rc.claude-lcls-bak"
        rewrite_stripped "$rc"
        ok "stripped from $rc (backup: $rc.claude-lcls-bak)"
      fi
    else
      ok "nothing to strip in $rc"
    fi
  done < <(rc_files)

  step "Shared skill links"
  SKILLS_DIR="$LCLS_DIR/skills"
  if [ -L "$SKILLS_DIR" ]; then
    # A whole-directory symlink is the broken state (see below). Remove the
    # LINK itself — never recurse through it into the shared tree.
    if [ "$DRY_RUN" = 1 ]; then
      echo "  (dry-run) would remove the symlink $SKILLS_DIR (link only, target untouched)"
    else
      rm -f "$SKILLS_DIR"
      ok "removed whole-directory symlink $SKILLS_DIR (shared tree untouched)"
    fi
  elif [ -d "$SKILLS_DIR" ]; then
    removed=0
    for link in "$SKILLS_DIR"/*; do
      [ -L "$link" ] || continue
      removed=$((removed + 1))
      if [ "$DRY_RUN" = 1 ]; then
        echo "  (dry-run) would remove symlink $link"
      else
        rm -f "$link"   # removes the link; the shared target is never followed
      fi
    done
    if [ "$DRY_RUN" = 1 ]; then
      echo "  (dry-run) would remove $removed skill symlink(s) and rmdir $SKILLS_DIR if empty"
    else
      rmdir "$SKILLS_DIR" 2>/dev/null || true
      ok "removed $removed skill symlink(s) from $SKILLS_DIR"
    fi
  else
    ok "no skills directory at $SKILLS_DIR"
  fi

  echo
  if [ -n "$SKIPPED_RCS" ]; then
    warn "left untouched and still needing manual repair:$SKIPPED_RCS"
    warn "the $FUNC_NAME block was NOT removed from the file(s) above."
    echo
  fi
  if [ -n "$UNWRITABLE_RCS" ]; then
    warn "not writable, left untouched:$UNWRITABLE_RCS"
    warn "the $FUNC_NAME block is STILL PRESENT in the file(s) above."
    warn "fix the permissions and re-run:  $0 --uninstall"
    echo
  fi
  echo "Config dir left in place: $LCLS_DIR"
  echo "Remove it yourself if you want it gone:  rm -rf $LCLS_DIR"
  echo "Your own ~/.claude/ was never touched."
  # An uninstall that left a block behind did not uninstall. Exiting 0 here told
  # a scripted caller the function was gone while claude-lcls() was still being
  # defined by the user's next shell.
  if [ -n "$SKIPPED_RCS$UNWRITABLE_RCS" ] && [ "$DRY_RUN" != 1 ]; then
    exit 1
  fi
  exit 0
fi

# ─── Preflight ────────────────────────────────────────────────────────────
step "Preflight"

# Resolve the claude binary. Exactly two sources, in this order:
#
#   1. $CLAUDE_LCLS_BIN   explicit, opt-in, for testing or an incident pin
#   2. $SHARED_BIN        the deployed team binary
#
# There is deliberately no third. Earlier versions of this script fell back to
# `command -v claude` and then to $HOME/.local/share/claude/versions/*, which
# made claude-lcls hostage to a personal install: the ~/.local/bin/claude
# launcher shim was observed vanishing from a home directory mid-campaign,
# leaving the function correctly installed and unable to start. It also meant
# two people running `claude-lcls` could silently be running two different
# Claude Code versions against the same gateway.
#
# A personal install is now never read. Your plain `claude` keeps working
# exactly as it did, against its own ~/.claude/ — this script does not touch it.
if [ -n "$CLAUDE_LCLS_BIN" ]; then
  CLAUDE_BIN="$CLAUDE_LCLS_BIN"
  warn "using CLAUDE_LCLS_BIN override: $CLAUDE_BIN"
  warn "unset it to go back to the shared team binary at $SHARED_BIN"
else
  CLAUDE_BIN="$SHARED_BIN"
fi

if [ ! -x "$CLAUDE_BIN" ]; then
  echo "  ✗ cannot run the Claude Code binary: $CLAUDE_BIN" >&2
  echo >&2
  if [ "$CLAUDE_BIN" = "$SHARED_BIN" ]; then
    # Same root cause as an unreadable key file, so give the same remedy rather
    # than sending people off to install Claude Code themselves — which is
    # exactly what this deployment exists to stop them having to do.
    echo "    The shared binary is deployed for 'ps-users'. You are in:" >&2
    echo "      $(id -nG)" >&2
    echo >&2
    echo "    If 'ps-users' is missing above, ask for membership — it is the same" >&2
    echo "    group that grants the gateway key and the shared skills." >&2
    echo >&2
    echo "    If you ARE in ps-users and this still fails, the deployment is at" >&2
    echo "    fault, not you. Report it rather than installing Claude Code" >&2
    echo "    yourself: this script no longer uses a personal install." >&2
  else
    echo "    CLAUDE_LCLS_BIN is set to a path that is not executable." >&2
    echo "    Unset it to use the shared team binary at $SHARED_BIN." >&2
  fi
  exit 1
fi

# A binary that exists and is executable but cannot RUN is a preflight failure,
# not a green checkmark with version "unknown".
CLAUDE_VER="$("$CLAUDE_BIN" --version 2>&1 | head -1)" \
  || die "'$CLAUDE_BIN' exists but failed to run: $CLAUDE_VER"
ok "claude found: $CLAUDE_BIN ($CLAUDE_VER)"
if [ "$CLAUDE_BIN" = "$SHARED_BIN" ] && [ -L "$SHARED_BIN" ]; then
  ok "shared team binary, resolving to $(readlink "$SHARED_BIN")"
fi

[ -r "$KEY_FILE" ] || {
  echo "  ✗ cannot read $KEY_FILE" >&2
  echo >&2
  echo "    This key is group-readable by 'ps-users'. You are in:" >&2
  echo "      $(id -nG)" >&2
  echo >&2
  echo "    Ask for 'ps-users' membership. Do NOT ask anyone to copy the key" >&2
  echo "    to you — it is meant to be read in place." >&2
  exit 1
}
ok "key readable: $KEY_FILE"

# Reachability. Gateway answers only on the SLAC network or VPN.
# The fallback MUST live outside the command substitution: curl writes 000 to
# stdout AND exits non-zero, so `|| echo 000` inside would concatenate to
# 000000 and this whole case would fall through to the catch-all.
HTTP_CODE="$(curl -s -o /dev/null -m 15 -w '%{http_code}' \
             -H "x-api-key: $(cat "$KEY_FILE")" \
             "$BASE_URL/v1/models" 2>/dev/null)" || HTTP_CODE=000
case "$HTTP_CODE" in
  200) ok "gateway reachable: $BASE_URL (HTTP 200)" ;;
  000) die "cannot reach $BASE_URL — are you on the SLAC network or VPN?" ;;
  401|403) die "gateway rejected the key (HTTP $HTTP_CODE). Key may be rotated or revoked." ;;
  *)   warn "gateway returned HTTP $HTTP_CODE — continuing, but verification may fail" ;;
esac

if [ -e "$HOME/.claude/settings.json" ]; then
  ok "your existing ~/.claude/settings.json will NOT be modified"
fi

# ─── Write the config dir ─────────────────────────────────────────────────
step "Config dir: $LCLS_DIR"

read -r -d '' SETTINGS_JSON <<EOF || true
{
  "\$schema": "https://json.schemastore.org/claude-code-settings.json",

  "apiKeyHelper": "cat $KEY_FILE",

  "env": {
    "ANTHROPIC_BASE_URL": "$BASE_URL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "us.anthropic.claude-opus-5[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "us.anthropic.claude-sonnet-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },

  "skipWebFetchPreflight": true,

  "attribution": {
    "commit": "Generated with AI\n\nCo-Authored-By: SLAC AI",
    "pr": ""
  }
}
EOF

if [ "$DRY_RUN" = 1 ]; then
  echo "  (dry-run) would create $LCLS_DIR/settings.json:"
  echo "$SETTINGS_JSON" | sed 's/^/      /'
else
  mkdir -p "$LCLS_DIR"
  chmod 700 "$LCLS_DIR"
  printf '%s\n' "$SETTINGS_JSON" > "$LCLS_DIR/settings.json"
  chmod 600 "$LCLS_DIR/settings.json"
  ok "wrote $LCLS_DIR/settings.json (mode 600)"
  ok "no key is stored — apiKeyHelper reads it from $KEY_FILE at runtime"
fi

# ─── Shared team skills ───────────────────────────────────────────────────
step "Shared skills: $SKILLS_SRC"

SKILLS_DIR="$LCLS_DIR/skills"

if [ ! -d "$SKILLS_SRC" ] || [ ! -r "$SKILLS_SRC" ]; then
  warn "shared skills root not readable: $SKILLS_SRC"
  warn "skipping skill links — the wrapper still works, you just get no team skills."
else
  if [ -L "$SKILLS_DIR" ]; then
    # Legacy/broken state: skills/ pointing at the shared directory as a whole.
    # Left in place, the mkdir -p below would follow the link and create a
    # directory INSIDE the live read-only deploy tree. Drop the link first.
    if [ "$DRY_RUN" = 1 ]; then
      echo "  (dry-run) would remove the whole-directory symlink $SKILLS_DIR"
    else
      rm -f "$SKILLS_DIR"
      warn "removed whole-directory symlink $SKILLS_DIR (shared tree untouched)"
    fi
  fi

  if [ "$DRY_RUN" = 1 ]; then
    echo "  (dry-run) would mkdir -p $SKILLS_DIR"
  else
    mkdir -p "$SKILLS_DIR"
  fi

  # Prune first: a skill retired from the shared tree must not leave a dangling
  # link behind forever. Only links that NO LONGER RESOLVE are removed, so this
  # can never follow a live link into the shared tree.
  pruned=0
  if [ -d "$SKILLS_DIR" ] && [ ! -L "$SKILLS_DIR" ]; then
    for old in "$SKILLS_DIR"/*; do
      [ -L "$old" ] || continue
      [ -e "$old" ] && continue          # target still resolves — keep
      pruned=$((pruned + 1))
      if [ "$DRY_RUN" = 1 ]; then
        echo "  (dry-run) would remove stale link $old"
      else
        rm -f "$old"
      fi
    done
  fi
  if [ "$pruned" -ne 0 ] && [ "$DRY_RUN" != 1 ]; then
    ok "pruned $pruned stale skill link(s) from $SKILLS_DIR"
  fi

  linked=0
  for src in "$SKILLS_SRC"/*; do
    if [ ! -e "$src" ]; then
      # A dangling symlink in the shared tree is how a skill gets retired by
      # mistake. Say so instead of dropping it on the floor.
      if [ -L "$src" ]; then
        warn "dangling entry in shared tree, not linked: $src"
      fi
      continue
    fi
    name="$(basename "$src")"
    # A REAL directory here would make `ln -sfn` create the link INSIDE it,
    # giving skills/$name/$name. Refuse rather than nest one level too deep.
    if [ -d "$SKILLS_DIR/$name" ] && [ ! -L "$SKILLS_DIR/$name" ]; then
      warn "$SKILLS_DIR/$name is a real directory, not a link — leaving it alone"
      continue
    fi
    linked=$((linked + 1))
    # One symlink per ENTRY. Never link or mkdir $SKILLS_SRC itself.
    if [ "$DRY_RUN" = 1 ]; then
      echo "  (dry-run) would link $SKILLS_DIR/$name -> $src"
    else
      ln -sfn "$src" "$SKILLS_DIR/$name"
    fi
  done

  if [ "$DRY_RUN" = 1 ]; then
    echo "  (dry-run) would link $linked shared skill(s) into $SKILLS_DIR"
  elif [ "$linked" -eq 0 ]; then
    warn "no skills found under $SKILLS_SRC — nothing linked"
  else
    ok "linked $linked shared skill(s) into $SKILLS_DIR"
  fi
fi

# ─── Install the shell function ───────────────────────────────────────────
step "Shell function: $FUNC_NAME()"

read -r -d '' SNIPPET <<EOF || true
$MARK_BEGIN
# Claude Code against the SLAC AI Gateway. Installed by install-claude-lcls.sh.
# Your plain \`claude\` is untouched and keeps using ~/.claude/.
#
# Runs the shared team binary, resolved at CALL time rather than baked to a
# version, so a bump or a rollback on the deploy side reaches you with nothing
# to re-run here. CLAUDE_LCLS_BIN overrides it if you deliberately set one; a
# personal install never does.
$FUNC_NAME() {
    local _bin="\${CLAUDE_LCLS_BIN:-$SHARED_BIN}"
    if [ ! -x "\$_bin" ]; then
        echo "$FUNC_NAME: shared Claude Code binary is not runnable: \$_bin" >&2
        echo "$FUNC_NAME: check you are still in ps-users -- id -nG" >&2
        return 127
    fi
    CLAUDE_CONFIG_DIR="$LCLS_DIR" "\$_bin" "\$@"
}
$MARK_END
EOF

while IFS= read -r rc; do
  # Checked before anything else: an rc we cannot write must not reach the
  # append below, where bash would report the failure in its own words.
  if ! rc_is_writable "$rc"; then
    skip_unwritable_rc "$rc"
    continue
  fi
  # An unterminated block cannot be stripped, and appending a fresh block on top
  # of it leaves two begin markers and one end marker — a shape the NEXT run
  # would "strip" by deleting every user line between them. Refuse instead.
  if [ -f "$rc" ] && has_unterminated_block "$rc"; then
    skip_broken_rc "$rc"
    continue
  fi
  if [ -f "$rc" ] && has_block "$rc"; then
    if [ "$DRY_RUN" = 1 ]; then
      echo "  (dry-run) would refresh the existing block in $rc"
    else
      cp -p "$rc" "$rc.claude-lcls-bak"
      rewrite_stripped "$rc"
      printf '\n%s\n' "$SNIPPET" >> "$rc"
      ok "refreshed in $rc"
    fi
  else
    if [ "$DRY_RUN" = 1 ]; then
      echo "  (dry-run) would append the $FUNC_NAME block to $rc"
    else
      printf '\n%s\n' "$SNIPPET" >> "$rc"
      ok "appended to $rc"
    fi
  fi
  # Reached only when the rc was neither skipped nor refused, so the block is
  # in (or, under DRY_RUN, would be in) this file.
  RC_INSTALLED=1
done < <(rc_files)

if [ -n "$SKIPPED_RCS" ]; then
  echo
  warn "left untouched and still needing manual repair:$SKIPPED_RCS"
  warn "$FUNC_NAME was NOT installed into the file(s) above; repair the markers and re-run."
fi

if [ -n "$UNWRITABLE_RCS" ]; then
  echo
  warn "not writable, left untouched:$UNWRITABLE_RCS"
  warn "$FUNC_NAME was NOT installed into the file(s) above; fix the permissions and re-run."
fi

# ONE verdict covering both refusal paths. What matters is not WHY an rc was
# refused but whether the block reached any rc at all:
#   * some rc took it -> warn about the ones that did not, and carry on to the
#     verification step, which is still worth running.
#   * none did        -> the script did not do its job, and says so with exit 1.
#     The previous shape exited 0 and printed the full "Done. Start a new
#     shell" banner having installed the function precisely nowhere.
# Everything else (config dir, settings.json, skill symlinks) is already in
# place and is deliberately left as-is, so a re-run finishes the job.
if [ -n "$SKIPPED_RCS$UNWRITABLE_RCS" ]; then
  if [ "$RC_INSTALLED" -eq 1 ]; then
    echo
    warn "$FUNC_NAME WAS installed into at least one other rc; continuing."
  elif [ "$DRY_RUN" = 1 ]; then
    echo
    warn "a real run would stop here with exit 1: no usable shell rc."
  else
    echo
    die "$FUNC_NAME could not be installed into ANY shell rc. Fix the file(s) above and re-run."
  fi
fi

# ─── Verify, for real ─────────────────────────────────────────────────────
step "Verification"

if [ "$DRY_RUN" = 1 ]; then
  echo "  (dry-run) would run a live one-shot completion through the new config"
  echo
  echo "Dry run complete. Nothing was written."
  exit 0
fi

# Run the same thing the shell function will run. This is the real test: it
# exercises apiKeyHelper, the gateway, the model aliases, AND whether a separate
# CLAUDE_CONFIG_DIR coexists with whatever auth state ~/.claude.json holds.
set +e
VERIFY_OUT="$(CLAUDE_CONFIG_DIR="$LCLS_DIR" "$CLAUDE_BIN" -p \
              'Reply with exactly: PONG' --model sonnet 2>&1)"
VERIFY_RC=$?
set -e

if [ $VERIFY_RC -eq 0 ] && printf '%s' "$VERIFY_OUT" | grep -q 'PONG'; then
  ok "live completion succeeded through $BASE_URL"
  echo
  echo "Done. Start a new shell (or: source ~/.bashrc), then:"
  echo
  echo "    $FUNC_NAME                       # interactive, SLAC gateway"
  echo "    $FUNC_NAME -p 'hello'            # one-shot"
  echo "    claude                           # your own setup, unchanged"
  echo
else
  warn "verification FAILED (exit $VERIFY_RC). The config is installed but unproven."
  echo
  echo "  Output was:" >&2
  printf '%s\n' "$VERIFY_OUT" | sed 's/^/    /' >&2
  echo >&2
  echo "  Things to check, in order:" >&2
  echo >&2
  echo "   1. Binary problems: claude-lcls runs ONLY the shared team binary" >&2
  echo "        $SHARED_BIN" >&2
  echo "      Check it directly:  $SHARED_BIN --version" >&2
  echo "      Permission denied or no such file usually means ps-users membership" >&2
  echo "      lapsed — check with 'id -nG'. Do NOT fix this by installing Claude" >&2
  echo "      Code into your home directory: this script does not use a personal" >&2
  echo "      install, so it would change nothing." >&2
  echo >&2
  echo "   2. Auth errors: confirm the key still works, independent of Claude Code:" >&2
  echo "        curl -s -o /dev/null -w '%{http_code}\\n' \\" >&2
  echo "          -H \"x-api-key: \$(cat $KEY_FILE)\" $BASE_URL/v1/models" >&2
  echo "      200 = fine. 000 = off the SLAC network/VPN. 401/403 = key problem." >&2
  echo >&2
  echo "   3. Model errors naming an id without the 'us.anthropic.' prefix mean an" >&2
  echo "      ANTHROPIC_DEFAULT_*_MODEL entry is missing from" >&2
  echo "      $LCLS_DIR/settings.json — all three are required." >&2
  echo >&2
  echo "  Your own ~/.claude/ and ~/.claude.json were not touched either way." >&2
  echo "  Remove this install with: $0 --uninstall" >&2
  exit 1
fi
