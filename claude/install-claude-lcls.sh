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
# claude-lcls also puts the shared team tools directory
# (/sdf/group/lcls/ds/dm/apps/dev/bin, where `uv` lives) FIRST on PATH for its
# own sessions only, so every `uv` a session runs -- a skill's or an agent's
# own -- is the team's uv, whether or not you installed one yourself. Your
# login shell's PATH is untouched; outside claude-lcls your own uv still wins.
#
# Usage:
#   ./install-claude-lcls.sh              # install (safe to re-run)
#   ./install-claude-lcls.sh --uninstall  # remove it again
#   ./install-claude-lcls.sh --dry-run    # show what would happen, write nothing
#   ./install-claude-lcls.sh --reset      # rebuild settings.json from the
#                                         # template, discarding local-only keys
#
# Re-running is genuinely safe for settings.json: the shared template is MERGED
# into your existing file, so keys the template does not define -- your theme,
# your model, your effortLevel, any env var you added -- survive. The template
# wins for the keys it does define. --reset opts out and rewrites wholesale.
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
RESET="${RESET:-0}"

# The shared team binary. A symlink into bin/versions/<ver>, so a version bump
# or a rollback is a symlink flip on the deploy side and needs no change here
# and no action from you. Never resolve this to a pinned version: the whole
# point is that the deployment decides which version everyone runs.
SHARED_BIN="${SHARED_BIN:-/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current}"

# Shared team tools, PREPENDED to PATH inside claude-lcls sessions. This is where
# `uv` lives, and many deployed skills (confluence-search, jira-search,
# elog-search, ask-slac-ai-tools, ...) run a bare `uv run` on a PEP 723 script,
# as do agents doing their own work. Nothing on S3DF puts this directory on PATH
# by default, so a ps-users member without a PERSONAL uv install had no uv at
# all -- while someone who happened to have one silently ran that instead.
#
# PREPENDED, not appended. This reverses the original call (commit 2fe258c),
# which appended so a personal uv would keep winning. In practice that meant a
# skill ran on whatever uv, uv config and Python a given user happened to have,
# which is the variation a centralized deployment exists to remove -- the same
# reason claude-lcls runs only the shared Claude binary. The skills' env.sh
# files already prepend this directory, but only when an agent remembers to
# source one; recorded claude-lcls sessions show bare `uv run` calls that did
# not. Doing it here covers every call. Measured on 2.1.267: the Bash tool
# keeps the PATH claude-lcls starts with, even when ~/.bashrc prepends
# ~/.local/bin unconditionally.
#
# Deliberately NOT exported alongside it: UV_PYTHON_INSTALL_DIR. Only the
# deployment owner can write $SHARED_PYTHON_DIR, so pointing every bare `uv` at
# it would turn a request for a Python it lacks into a hard "Permission denied"
# (without it, uv downloads one into your home), and would let the owner's sessions
# install or uninstall the interpreters the skills depend on. The skills that
# need the shared Pythons set it themselves, in their env.sh.
SHARED_TOOLS_BIN="${SHARED_TOOLS_BIN:-/sdf/group/lcls/ds/dm/apps/dev/bin}"

# The shared uv-managed Python installs, and which one to use for the
# settings.json merge below. Pointing UV_PYTHON_INSTALL_DIR here means `uv run
# --python 3.11` resolves against the team's existing interpreters instead of
# downloading one -- compute nodes have no default internet route, so a fetch
# would be a latent failure rather than a slow success.
SHARED_PYTHON_DIR="${SHARED_PYTHON_DIR:-/sdf/group/lcls/ds/dm/apps/dev/python}"
SHARED_PYTHON="${SHARED_PYTHON:-3.11}"

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
    --reset)     RESET=1 ;;
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

# Shared tools are a convenience, not a requirement -- most skills do not need
# uv, and the wrapper still works without it. So this warns and continues rather
# than dying, unlike the binary and the key.
if [ -x "$SHARED_TOOLS_BIN/uv" ]; then
  ok "shared tools first on PATH: $SHARED_TOOLS_BIN (uv $("$SHARED_TOOLS_BIN/uv" --version 2>/dev/null | awk '{print $2}'))"
  # Say so when this changes which uv someone gets, rather than letting a
  # personal uv vanish from their sessions without a word.
  _own_uv="$(command -v uv 2>/dev/null || true)"
  if [ -n "$_own_uv" ] && [ "$_own_uv" != "$SHARED_TOOLS_BIN/uv" ]; then
    ok "your own uv ($_own_uv) is shadowed inside $FUNC_NAME sessions only; your shell keeps it"
  fi
else
  warn "shared tools dir has no runnable uv: $SHARED_TOOLS_BIN"
  warn "skills that call 'uv run' will fail unless you have your own uv on PATH"
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

# Two kinds of key live in this file and it is worth keeping them apart.
#
# REQUIRED. apiKeyHelper and env.ANTHROPIC_BASE_URL are what make claude-lcls
# work at all; apiKeyHelper alone sends the SLAC key to api.anthropic.com and
# comes back 401.
#
# TEAM DEFAULTS -- everything from "permissions" down. These are preferences,
# not requirements: the wrapper works without them. They are set here so that
# everyone starts from the same terminal behaviour rather than from whatever
# each Claude Code release happens to default to.
#
#   permissions.defaultMode "auto"  Claude classifies each action and prompts
#                                   only for the ones that need a human. Note
#                                   that ONLY a user-level settings file may
#                                   grant this -- a repo-level one cannot. This
#                                   file is the user-level one, because
#                                   CLAUDE_CONFIG_DIR points at its directory.
#   tui "fullscreen"                the fullscreen renderer, i.e. what you would
#                                   get by running /tui fullscreen every session.
#   verbose false                   truncated tool output rather than full.
#   showThinkingSummaries false     no API-side thinking summaries.
#   autoMemoryEnabled false         Claude neither reads nor writes the
#                                   auto-memory directory.
# MODEL WIRING. The four ANTHROPIC_DEFAULT_*_MODEL entries map Claude Code's
# opus / sonnet / haiku / fable aliases onto the Bedrock ids the SLAC gateway
# serves, so /model opus selects Opus 5.5, /model sonnet selects Sonnet 5 and
# /model fable selects Fable 5.1. The gateway offers more than those four --
# Opus 5, 4.8, 4.7, 4.6 and Sonnet 4.6 are all live on it -- but an alias can
# only point at one id.
#
# OPUS 5.5 NEEDS 2.1.285+. 2.1.267 has zero occurrences of "opus-5-5": it still
# answers, but logs [claude-code:unrecognized_model], caps output at 32000
# instead of 128000 and prices the session at Opus 5 rates. 2.1.285 recognizes
# it and reports 1000000 / 128000 with or without [1m]. The suffix stays anyway
# so that a rollback to 2.1.267 keeps the 1M window. Measured 2026-10-07.
#
# ANTHROPIC_DEFAULT_FABLE_MODEL also makes /model best resolve to Fable 5.1,
# since `best` means "Fable where available, otherwise Opus". Anthropic's docs
# say the fable alias wants 2.1.257+, but 2.1.235 resolved both `fable` and
# `best` to us.anthropic.claude-fable-5-1 once this var was set -- measured
# 2026-09-19, not inferred.
#
# THE [1m] SUFFIX IS LOAD-BEARING, and only here. Measured on 2.1.235 against
# this gateway: a plain us.anthropic.claude-sonnet-5 reports contextWindow
# 200000 while us.anthropic.claude-sonnet-5[1m] reports 1000000, and both
# return a completion -- Claude Code strips the suffix before the request
# leaves. Fable 5.1 behaves the same way. Newer binaries may report 1M from the
# plain id, so re-measure with `--output-format json` after a pin bump rather
# than assuming either form.
#
# Do NOT carry these suffixed ids into opencode.json. opencode does not strip
# the suffix, and the gateway answers slac/us.anthropic.claude-opus-5[1m] with
# 400 Invalid model name passed in model=... Use the plain id there; it already
# advertises 1M input / 128k output.
#
# ANTHROPIC_CUSTOM_MODEL_OPTION is how anything else reaches the picker. Claude
# Code APPENDS it to the model list rather than replacing an entry, using
# _NAME as the label and _DESCRIPTION as the subtitle. It is a SINGLE slot:
# there is no numbered second one, so exactly one extra model can be offered and
# Sonnet 4.6 is the one chosen. Anyone needing a different one can still name it
# explicitly with `claude-lcls --model us.anthropic.claude-opus-4-8`; the slot
# only decides what appears in the menu without being typed.
#
# All five ids were answered by the gateway on 2026-09-19: opus-5[1m],
# sonnet-5[1m], fable-5-1[1m], sonnet-4-6 and haiku-4-5 each returned a
# completion, exit 0. `GET /v1/models` lists fable-5-1, opus-5 and sonnet-5 at
# 1M input / 128k output. opus-5-5 was added 2026-10-07; the listing shows it at
# 200k / 64k, but that metadata is stale -- a 215k-token request succeeded.
#
# PROMPT CACHE TTL. promptCacheTtl "1h" keeps the main conversation's cached
# prefix alive through an hour-long gap instead of five minutes, which is what
# an idle-then-resume session wants; 1h cache writes bill at 2x base input
# against 1.25x for 5m, so it costs more on short bursts that never idle.
#
# It is scoped to the MAIN CONVERSATION only. Subagents, compaction and session
# titles keep the five-minute default because subagentPromptCacheTtl is left
# unset deliberately. The older ENABLE_PROMPT_CACHING_1H=1 applies the hour to
# both buckets at once and is the 2.1.235-compatible fallback.
#
# promptCacheTtl NEEDS 2.1.242+. A scan of 2.1.235 finds zero occurrences of
# promptCacheTtl, subagentPromptCacheTtl or CLAUDE_CODE_PROMPT_CACHE_TTL, so on
# that binary this key is one of the silently-ignored near-misses described
# below. 2.1.267 has all three. Confirm the hour actually reaches the gateway
# with `claude -p hello --output-format json` and a non-zero
# usage.cache_creation.ephemeral_1h_input_tokens -- part of the 1h request rides
# in the anthropic-beta header, so a gateway that drops that header, or
# CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS above, can leave it at 5m while
# everything still appears to work.
#
# OPUS 5.5 IS THE EXCEPTION: the gateway caches it for 5 minutes only. A raw
# request with cache_control ttl "1h" lands in ephemeral_5m for opus-5-5 and in
# ephemeral_1h for sonnet-5, with or without the extended-cache-ttl beta, so
# this is gateway-side and no client setting fixes it. Accepted for now
# (2026-10-07); re-check after any gateway change.
#
#   env.DISABLE_AUTOUPDATER "1"     no self-update. Belt and braces: the updater
#                                   is ALREADY off without it, because
#                                   CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC a
#                                   few lines up disables it too. Naming it
#                                   directly means that dropping the traffic flag
#                                   later cannot silently re-enable updates.
#
# verbose and showThinkingSummaries pin what 2.1.235 already defaults to; the
# other three change behaviour. Auto-memory in particular is ON unless this
# says otherwise.
#
# The shared pin moved from 2.1.235 to 2.1.267 on 2026-09-19 (see
# tools/claude-binary/env.sh) to get promptCacheTtl. A string scan of 2.1.267
# still finds autoMemoryEnabled, showThinkingSummaries and DISABLE_AUTOUPDATER,
# so every key written below survives the bump. Two caveats: a key's presence in
# the binary is not proof its DEFAULT is unchanged, and the "already defaults to"
# claim a few lines up was measured on 2.1.235 only. 2.1.267 additionally has
# modelSettings, which 2.1.235 lacks entirely -- that is the mechanism if a
# per-model default effort level is ever wanted here.
#
# The pin moved again, to 2.1.285, on 2026-10-07 for Opus 5.5. A string scan
# finds every key written below in 2.1.285 too, and all five aliases (opus,
# sonnet, fable, best, haiku) answered on the staged binary before publishing.
#
# Two things measured against the 2.1.235 binary that are easy to get wrong:
#
#   1. There is no "memory" object and no "autoMemory" key in the settings
#      schema. The real key is top-level "autoMemoryEnabled". Neither 2.1.235
#      nor 2.1.251 has ever had the other spelling.
#   2. There is no settings KEY for the auto-updater. env.DISABLE_AUTOUPDATER
#      is the supported control -- it is literally what Claude Code's own
#      settings migration writes when a user turns auto-updates off. In 2.1.235
#      the updater gate reports itself disabled for any of DISABLE_UPDATES,
#      DISABLE_AUTOUPDATER or CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC, so this
#      deployment was already covered by the third; the entry is here to say so
#      out loud. A shared read-only binary is not one a user could update anyway.
#
# Both matter more than they look, because Claude Code ignores unknown settings
# keys in SILENCE. A near-miss spelling produces no warning, no error and no
# effect, so it reads as working. Verified by installing a deliberately bogus
# key and watching a one-shot exit 0 with empty stderr.
#
# A user who wants different values can edit this file, but re-running this
# installer rewrites it -- so note any local change somewhere it will survive.
read -r -d '' SETTINGS_JSON <<EOF || true
{
  "\$schema": "https://json.schemastore.org/claude-code-settings.json",

  "apiKeyHelper": "cat $KEY_FILE",

  "env": {
    "ANTHROPIC_BASE_URL": "$BASE_URL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "us.anthropic.claude-opus-5-5[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "us.anthropic.claude-sonnet-5[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "us.anthropic.claude-fable-5-1[1m]",
    "ANTHROPIC_CUSTOM_MODEL_OPTION": "us.anthropic.claude-sonnet-4-6",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_NAME": "Sonnet 4.6",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION": "Previous Sonnet, kept selectable via the SLAC gateway",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_AUTOUPDATER": "1"
  },

  "promptCacheTtl": "1h",

  "skipWebFetchPreflight": true,

  "attribution": {
    "commit": "Generated with AI\n\nCo-Authored-By: SLAC AI",
    "pr": ""
  },

  "permissions": {
    "defaultMode": "auto"
  },

  "tui": "fullscreen",
  "verbose": false,
  "showThinkingSummaries": false,
  "autoMemoryEnabled": false
}
EOF

SETTINGS_DST="$LCLS_DIR/settings.json"

if [ "$DRY_RUN" = 1 ]; then
  if [ -f "$SETTINGS_DST" ] && [ "$RESET" = 0 ]; then
    echo "  (dry-run) would MERGE this template into the existing $SETTINGS_DST,"
    echo "  (dry-run) keeping every key the template does not define (--reset to overwrite):"
  else
    echo "  (dry-run) would create $SETTINGS_DST:"
  fi
  echo "$SETTINGS_JSON" | sed 's/^/      /'
else
  mkdir -p "$LCLS_DIR"
  chmod 700 "$LCLS_DIR"

  # Merging needs a JSON parser. Prefer the SHARED uv-managed python -- the same
  # centralized interpreter the deployed skills reach for -- so the result does
  # not depend on whatever python a given login node happens to ship. Measured
  # under `env -i PATH=/usr/bin:/bin`: 3.11.14 in ~50 ms, nothing fetched,
  # because UV_PYTHON_INSTALL_DIR points at the shared install dir.
  #
  # Same resolution shape as skills/docs-search/scripts/docs-index: try the
  # shared copy first, then whatever is on PATH, then give up loudly. The system
  # python3 on S3DF is 3.6.8, which parses JSON fine but is not something to
  # depend on by choice.
  MERGE_CMD=()
  if [ -x "$SHARED_TOOLS_BIN/uv" ] \
     && UV_PYTHON_INSTALL_DIR="$SHARED_PYTHON_DIR" "$SHARED_TOOLS_BIN/uv" \
          run --python "$SHARED_PYTHON" --no-project python -c 'import json' >/dev/null 2>&1; then
    MERGE_CMD=(env "UV_PYTHON_INSTALL_DIR=$SHARED_PYTHON_DIR" "$SHARED_TOOLS_BIN/uv" \
               run --python "$SHARED_PYTHON" --no-project python)
  else
    for _cand in python3 /usr/bin/python3; do
      if command -v "$_cand" >/dev/null 2>&1 && "$_cand" -c 'import json' >/dev/null 2>&1; then
        MERGE_CMD=("$_cand"); break
      fi
    done
  fi

  if [ ! -f "$SETTINGS_DST" ]; then
    printf '%s\n' "$SETTINGS_JSON" > "$SETTINGS_DST"
    chmod 600 "$SETTINGS_DST"
    ok "wrote $SETTINGS_DST (mode 600)"
  else
    _bk="$SETTINGS_DST.bak-$(date +%Y%m%d%H%M%S)"
    cp -p "$SETTINGS_DST" "$_bk"

    if [ "$RESET" = 1 ] || [ ${#MERGE_CMD[@]} -eq 0 ]; then
      printf '%s\n' "$SETTINGS_JSON" > "$SETTINGS_DST"
      chmod 600 "$SETTINGS_DST"
      if [ "$RESET" = 1 ]; then
        ok "--reset: rebuilt $SETTINGS_DST from the template (previous copy: $_bk)"
      else
        warn "no JSON-capable python found, not even $SHARED_TOOLS_BIN/uv --"
        warn "wrote the template wholesale. Any local-only keys are still in"
        warn "$_bk; merge them back by hand."
      fi
    else
      _tmpl="$(mktemp "${TMPDIR:-/tmp}/claude-lcls-tmpl.XXXXXX")"
      _mrg="$(mktemp "${TMPDIR:-/tmp}/claude-lcls-merge.XXXXXX")"
      printf '%s\n' "$SETTINGS_JSON" > "$_tmpl"
      cat > "$_mrg" <<'MERGE_PYEOF'
import collections, json, sys

dst, tmpl = sys.argv[1], sys.argv[2]

def load(path):
    with open(path) as fh:
        return json.load(fh, object_pairs_hook=collections.OrderedDict)

try:
    have = load(dst)
except Exception as exc:
    sys.stderr.write("existing settings.json is not valid JSON: %s\n" % exc)
    sys.exit(3)
want = load(tmpl)

preserved = []

def merge(base, over, path=""):
    # Recursive, so a user-added entry inside "env" survives while the template
    # still updates the env vars it actually names.
    out = collections.OrderedDict()
    for key, val in base.items():
        full = path + key
        if key in over:
            if isinstance(val, dict) and isinstance(over[key], dict):
                out[key] = merge(val, over[key], full + ".")
            else:
                out[key] = over[key]
        else:
            out[key] = val
            preserved.append(full)
    for key, val in over.items():
        if key not in out:
            out[key] = val
    return out

merged = merge(have, want)
with open(dst, "w") as fh:
    json.dump(merged, fh, indent=2)
    fh.write("\n")
print(" ".join(preserved))
MERGE_PYEOF

      set +e
      _kept="$("${MERGE_CMD[@]}" "$_mrg" "$SETTINGS_DST" "$_tmpl" 2>&1)"
      _rc=$?
      set -e

      if [ $_rc -eq 0 ]; then
        chmod 600 "$SETTINGS_DST"
        ok "merged the shared template into $SETTINGS_DST (mode 600)"
        if [ -n "$_kept" ]; then
          ok "kept your local-only key(s): $_kept"
        fi
        # Keep a backup only when it differs, so re-running does not litter the
        # directory with identical copies.
        if cmp -s "$_bk" "$SETTINGS_DST"; then
          rm -f "$_bk"
          ok "settings.json was already up to date"
        else
          ok "previous copy: $_bk"
        fi
      else
        cp -p "$_bk" "$SETTINGS_DST"
        rm -f "$_bk"
        warn "could not merge settings.json: $_kept"
        warn "your existing file was left exactly as it was."
        warn "fix the JSON, or re-run with --reset to rebuild from the template."
      fi
      rm -f "$_tmpl" "$_mrg"
    fi
  fi
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
    # Shared team tools (uv, docs-index) FIRST on PATH, so every \`uv\` this
    # session runs -- a skill's or an agent's own -- is the team's uv, even if
    # you have one yourself. Any copy already on PATH is removed first, so
    # nesting claude-lcls keeps exactly one entry. Your shell's PATH is untouched.
    local _rest=":\$PATH:"
    while :; do
        case "\$_rest" in
            *":$SHARED_TOOLS_BIN:"*)
                _rest="\${_rest%%:$SHARED_TOOLS_BIN:*}:\${_rest#*:$SHARED_TOOLS_BIN:}" ;;
            *) break ;;
        esac
    done
    _rest="\${_rest#:}"; _rest="\${_rest%:}"
    PATH="$SHARED_TOOLS_BIN\${_rest:+:\$_rest}" CLAUDE_CONFIG_DIR="$LCLS_DIR" "\$_bin" "\$@"
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

# Which uv a session will find, checked through the function text just
# installed rather than a re-derivation of it: /bin/sh stands in for the Claude
# binary and reports what `uv` resolves to under the PATH the function built.
if [ -x "$SHARED_TOOLS_BIN/uv" ]; then
  SESSION_UV="$(bash -c "$SNIPPET"$'\n'"CLAUDE_LCLS_BIN=/bin/sh $FUNC_NAME -c 'command -v uv'" 2>/dev/null || true)"
  if [ "$SESSION_UV" = "$SHARED_TOOLS_BIN/uv" ]; then
    ok "uv inside $FUNC_NAME sessions: $SESSION_UV"
  else
    warn "uv inside $FUNC_NAME sessions resolves to '${SESSION_UV:-nothing}', not $SHARED_TOOLS_BIN/uv"
  fi
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
