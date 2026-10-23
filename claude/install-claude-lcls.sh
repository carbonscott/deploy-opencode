#!/usr/bin/env bash
# Install `claude-lcls` — Claude Code pointed at the SLAC AI Gateway.
#
# Gives you a `claude-lcls` command that runs Claude Code against
# https://ai-api.slac.stanford.edu using your own key file and the shared
# team binary, WITHOUT touching your existing `claude` setup (personal
# subscription, API key, whatever you already have). The two live side by side:
#
#     claude        -> your own install and ~/.claude/, untouched
#     claude-lcls   -> shared binary, SLAC gateway, your key, ~/.claude-lcls/
#
# API KEYS. claude-lcls reads its gateway key from ONE file of your own,
# ~/.config/slac-ai/key.dat (mode 600). The `keyswitch` tool writes that file
# from the keys you keep encrypted in your own pass store
# (https://www.passwordstore.org/), under slac-ai/<name>. The installer
# registers the shared LCLS key as your first key, slac-ai/shared, and uses
# it -- unless you paste a personal key when it asks; that one is stored as
# slac-ai/personal and used instead. Re-running never moves you off a key you
# chose. Later, in a new shell:
#
#     keyswitch -s slac-ai add personal --use   # store a new key and use it
#     keyswitch -s slac-ai use shared           # switch to another stored key
#     keyswitch -s slac-ai list                 # * marks the key in use
#
# With no pass store (no terminal to ask in, or you said no), the installer
# writes key.dat directly. Re-run it in a terminal to set up keyswitch.
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

# Per-user keys (see "API key" below). KEY_FILE above is the SHARED LCLS key;
# USER_KEY_FILE is the one file claude-lcls reads, one per user, mode 600.
# keyswitch writes it from the user's pass store; the installer writes it
# directly only when there is no store. keyswitch, its check program and pass
# are deployed centrally; pass is used only when you have none of your own.
USER_KEY_FILE="${USER_KEY_FILE:-$HOME/.config/slac-ai/key.dat}"
KEYSWITCH_BIN="${KEYSWITCH_BIN:-/sdf/group/lcls/ds/dm/apps/dev/keyswitch/current/bin/keyswitch}"
KEYSWITCH_CHECK_HTTP="${KEYSWITCH_CHECK_HTTP:-/sdf/group/lcls/ds/dm/apps/dev/keyswitch/current/bin/keyswitch-check-http}"
SHARED_PASS="${SHARED_PASS:-/sdf/group/lcls/ds/dm/apps/dev/pass/current/bin/pass}"
# The keyswitch service: its pass folder is slac-ai/ and its settings file
# is slac-ai.conf. Not overridable: the docs and messages name it.
KS_SERVICE=slac-ai
# Folders whose writers keyswitch is told to trust (see ks_global_content).
KS_TRUSTED_DIRS="/sdf/group/lcls:/sdf/group/lcls/ds/dm/apps/dev"

# These names hold key material below. If the caller happened to export one,
# bash would keep the export flag and hand the key to every child process.
unset -v SHARED_KEY TYPED_KEY EXISTING_KEY _in

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

# Where keyswitch will look for its settings and where pass keeps its store,
# found the same way keyswitch and pass find them, so the installer writes
# exactly what a later `keyswitch` in the same environment reads.
KS_DIR="${KEYSWITCH_CONFIG_DIR:-}"
# shellcheck disable=SC2088  # the '~' patterns match a literal tilde
case "$KS_DIR" in
  '')
    case "${XDG_CONFIG_HOME:-}" in
      /*) KS_DIR="$XDG_CONFIG_HOME/keyswitch" ;;
      *)  KS_DIR="$HOME/.config/keyswitch" ;;
    esac ;;
  '~'|'~/'*) KS_DIR="$HOME${KS_DIR#\~}" ;;
  /*) ;;
  *) die "KEYSWITCH_CONFIG_DIR must be an absolute path (got: $KS_DIR)" ;;
esac
KS_STORE="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

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
  echo
  # Keys are never deleted here: they may be personal, and other tools may
  # read the same file or store.
  echo "Your API keys were left in place too:"
  echo "    key file            $USER_KEY_FILE"
  echo "    pass store          $KS_STORE   (keys under $KS_SERVICE/)"
  echo "    keyswitch settings  $KS_DIR"
  echo "Remove them yourself only if nothing else uses them."
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
  echo "    Ask for 'ps-users' membership; the shared binary and skills need" >&2
  echo "    it too." >&2
  exit 1
}
# Read ONCE into a variable. From here on the key is never printed and never
# put on a command line -- argv is world-visible in `ps` on a shared login
# node. It reaches curl, keyswitch and key.dat only on stdin or through a
# builtin printf.
SHARED_KEY=""
IFS= read -r SHARED_KEY < "$KEY_FILE" || [ -n "$SHARED_KEY" ] \
  || die "$KEY_FILE is empty"
SHARED_KEY="${SHARED_KEY%$'\r'}"
[ -n "$SHARED_KEY" ] || die "the first line of $KEY_FILE is empty"
ok "shared key readable: $KEY_FILE"

# Reachability. Gateway answers only on the SLAC network or VPN.
# The fallback MUST live outside the command substitution: curl writes 000 to
# stdout AND exits non-zero, so `|| echo 000` inside would concatenate to
# 000000 and this whole case would fall through to the catch-all.
# The header goes in on stdin (-H @-); -q, which must come first, keeps a
# ~/.curlrc from adding redirects or tracing that would send it elsewhere.
HTTP_CODE="$(printf 'x-api-key: %s\n' "$SHARED_KEY" \
             | curl -q -s -o /dev/null -m 15 -w '%{http_code}' -H @- \
                    "$BASE_URL/v1/models" 2>/dev/null)" || HTTP_CODE=000
case "$HTTP_CODE" in
  200) ok "gateway reachable: $BASE_URL (HTTP 200)" ;;
  000) die "cannot reach $BASE_URL — are you on the SLAC network or VPN?" ;;
  401|403) die "gateway rejected the shared key (HTTP $HTTP_CODE). Key may be rotated or revoked." ;;
  *)   warn "gateway returned HTTP $HTTP_CODE — continuing, but verification may fail" ;;
esac

# apiKeyHelper below is `cat <this path>`, unquoted inside a JSON string, so
# the path must need neither shell quoting nor JSON escaping.
case "$USER_KEY_FILE" in
  /*) ;;
  *)  die "USER_KEY_FILE must be an absolute path (got: $USER_KEY_FILE)" ;;
esac
case "$USER_KEY_FILE" in
  *[!A-Za-z0-9._/@+-]*)
    die "USER_KEY_FILE has characters apiKeyHelper cannot take unquoted: $USER_KEY_FILE. Set USER_KEY_FILE to a plain path and re-run." ;;
esac

if [ -e "$HOME/.claude/settings.json" ]; then
  ok "your existing ~/.claude/settings.json will NOT be modified"
fi

# ─── API key ──────────────────────────────────────────────────────────────
step "API key: $USER_KEY_FILE"

# WHY A FILE OF YOUR OWN. Until 2026-10 apiKeyHelper read the shared key in
# place: ~30 people on one key and one monthly budget, readable by all of
# ps-users, with no way to tell anyone's use apart. IT and Cyber asked for
# per-person keys. Now apiKeyHelper reads $USER_KEY_FILE, one per user, and
# keyswitch (https://github.com/carbonscott/keyswitch) writes it from keys the
# user keeps encrypted in their own pass store, under slac-ai/<name>.
#
# What this section does, in order:
#   1. In a terminal only (never under --dry-run): ask for a personal key and
#      check it with the gateway before going on.
#   2. Write keyswitch's settings: `config` merged, slac-ai.conf rewritten.
#   3. Find the pass store, or (terminal only) offer to create one.
#   4. With a store: register the shared key as slac-ai/shared on EVERY run,
#      so a rotated shared key is picked up, and a pasted key as
#      slac-ai/personal. The pasted key is put in use; the shared key only
#      when keyswitch reports no key in use, or reports 'shared' itself.
#   5. Without one, or when keyswitch fails: write key.dat directly, by the
#      same rules.
# Re-running must never move someone back to the shared key: a key they chose
# -- a keyswitch entry, or a key sitting in key.dat that the gateway still
# accepts -- is kept.

# Exit 0 = the gateway accepts the key, 1 = it rejects it (HTTP 401/403),
# 3 = could not check. The key arrives as $1 and leaves on stdin only.
# keyswitch-check-http is the very check keyswitch runs; the inline curl
# stands in for it when keyswitch is not deployed.
check_key() {
  local code rc=0
  if [ -x "$KEYSWITCH_CHECK_HTTP" ]; then
    printf '%s\n' "$1" | "$KEYSWITCH_CHECK_HTTP" "$BASE_URL/v1/models" x-api-key \
      2>/dev/null || rc=$?
    case $rc in 0|1) return $rc ;; *) return 3 ;; esac
  fi
  code="$(printf 'x-api-key: %s\n' "$1" \
          | curl -q -s -o /dev/null -m 20 -w '%{http_code}' -H @- \
                 "$BASE_URL/v1/models" 2>/dev/null)" || code=000
  case "$code" in
    2??)     return 0 ;;
    401|403) return 1 ;;
    *)       return 3 ;;
  esac
}

# Store a key ($2) in pass as slac-ai/<name> ($1) through keyswitch, which
# checks it with the gateway first. More flags (--force, --use) follow. The
# key goes in on stdin; keyswitch's own output is shown indented.
ks_add() {
  local name="$1" key="$2" out rc=0
  shift 2
  out="$(printf '%s\n' "$key" \
         | "$KEYSWITCH_BIN" -s "$KS_SERVICE" add "$name" "$@" 2>&1)" || rc=$?
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/      /'
  return $rc
}

# Write $1 to $USER_KEY_FILE: folder 700, file 600, through a temp file in the
# same folder and a rename, so the file never holds half a key.
write_user_key() {
  local dir tmp
  dir="$(dirname "$USER_KEY_FILE")"
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.key.dat.XXXXXX")" || return 1
  if printf '%s\n' "$1" > "$tmp" && chmod 600 "$tmp" \
     && mv -fT "$tmp" "$USER_KEY_FILE"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Replace file $1 with stdin, mode 600, through a temp file and a rename. An
# identical file is left alone; a different one is backed up first.
install_private_file() {
  local dst="$1" tmp bk=""
  tmp="$(mktemp "$(dirname "$dst")/.$(basename "$dst").XXXXXX")" || return 1
  if ! { cat > "$tmp" && chmod 600 "$tmp"; }; then
    rm -f "$tmp"
    return 1
  fi
  if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then
    rm -f "$tmp"
    chmod 600 "$dst"
    ok "$dst is up to date"
    return 0
  fi
  if [ -f "$dst" ]; then
    bk="$dst.bak-$(date +%Y%m%d%H%M%S)"
    cp -p "$dst" "$bk"
  fi
  mv -f "$tmp" "$dst" || return 1
  ok "wrote $dst${bk:+ (previous copy: $bk)}"
}

# keyswitch's own settings file, `config`. MERGED, never rewritten: every line
# already there stays. Two settings may be added, each at most once, because
# keyswitch refuses a setting given twice:
#   trusted_dirs  keyswitch walks every folder above a program that sees a key
#                 (pass, the gateway check) and refuses one that a group or
#                 everyone can write unless it is listed here. /sdf/group/lcls
#                 is group-writable (ps-pcds) and .../apps/dev shows 775
#                 through its ACL mask; the central keyswitch and pass live
#                 below both. Our folders are appended to an existing value.
#   pass          the central pass, ONLY when there is no pass on your PATH
#                 and no `pass =` line already. Never overrides your own.
# $1 = the current file (or /dev/null), $2 = 1 to add `pass =`. Prints the result.
ks_global_content() {
  awk -v dirs="$KS_TRUSTED_DIRS" -v want_pass="$2" -v pass_bin="$SHARED_PASS" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function has(list, d,   n, i, p, x) {
      n = split(list, p, ":")
      for (i = 1; i <= n; i++) { x = trim(p[i]); sub(/\/+$/, "", x); if (x == d) return 1 }
      return 0
    }
    function why() {
      print "# Added by install-claude-lcls.sh. keyswitch refuses to run a program that"
      print "# sees your keys (pass, the gateway check) from a folder other people can"
      print "# change, unless the folder is listed here. /sdf/group/lcls is writable by"
      print "# ps-pcds, and /sdf/group/lcls/ds/dm/apps/dev shows 775 through its ACL"
      print "# mask. The claude-lcls binary and skills already live under these folders,"
      print "# so trusting them adds no new exposure."
    }
    { t = trim($0) }
    t ~ /^trusted_dirs[ \t]*=/ && !td {
      td = 1
      val = trim(substr(t, index(t, "=") + 1))
      n = split(dirs, want, ":"); add = ""
      for (i = 1; i <= n; i++) if (!has(val, want[i])) add = add ":" want[i]
      if (add == "") { print; next }
      if (prev !~ /adds no new exposure/) why()
      print "trusted_dirs = " (val == "" ? substr(add, 2) : val add)
      prev = ""
      next
    }
    t ~ /^pass[ \t]*=/ { has_pass = 1 }
    { print; prev = $0 }
    END {
      if (!td) { if (NR) print ""; why(); print "trusted_dirs = " dirs }
      if (want_pass && !has_pass) {
        print ""
        print "# Added by install-claude-lcls.sh because no pass was on your PATH: the"
        print "# central copy. Delete these lines to use a pass of your own instead."
        print "pass = " pass_bin
      }
    }' "$1"
}

# The slac-ai service file. Owned by the installer and rewritten every run.
# `check` is ONE command and its arguments: keyswitch accepts no $VARS, pipes
# or redirections there.
ks_service_content() {
  local target="$USER_KEY_FILE"
  # shellcheck disable=SC2088  # a literal ~ is what keyswitch expects here
  case "$target" in "$HOME"/*) target="~/${target#"$HOME"/}" ;; esac
  printf '%s\n' \
    "# Written by install-claude-lcls.sh; re-running the installer rewrites this file." \
    "entries = $KS_SERVICE/" \
    "target = $target" \
    "check = $KEYSWITCH_CHECK_HTTP $BASE_URL/v1/models x-api-key" \
    "message = Restart $FUNC_NAME to use it now; sessions already open switch on their own within 5 minutes."
}

write_ks_config() {
  local src=/dev/null want_pass=0
  [ -n "$OWN_PASS" ] || want_pass=1
  mkdir -p "$KS_DIR" || return 1
  [ -O "$KS_DIR" ] || { warn "$KS_DIR belongs to someone else"; return 1; }
  chmod 700 "$KS_DIR" || return 1
  [ -f "$KS_DIR/config" ] && src="$KS_DIR/config"
  ks_global_content "$src" "$want_pass" | install_private_file "$KS_DIR/config" \
    || return 1
  ks_service_content | install_private_file "$KS_DIR/$KS_SERVICE.conf"
}

# Secret keys that can encrypt and are not revoked, expired or disabled, one
# "FINGERPRINT<TAB>USER ID" line each.
gpg_secret_keys() {
  "$GPG_BIN" --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '
    function flush() { if (ok && fpr != "") printf "%s\t%s\n", fpr, uid; ok = 0; fpr = ""; uid = "" }
    $1 == "sec" { flush(); ok = ($2 !~ /[redin]/ && $12 ~ /E/ && $12 !~ /D/); want = 1; next }
    $1 == "fpr" && want { fpr = $10; want = 0; next }
    $1 == "uid" && uid == "" { uid = $10; next }
    $1 == "ssb" { want = 0 }
    END { flush() }'
}

# Ask on the terminal; Enter means yes.
ask_yes() {
  local a=""
  IFS= read -r -p "  $1 [Y/n] " a || a=n
  case "$a" in ''|[Yy]|[Yy][Ee][Ss]) return 0 ;; *) return 1 ;; esac
}

# Terminal only: offer to make the pass store, with an existing GnuPG key or a
# new one. Returns 0 once $KS_STORE/.gpg-id exists, 1 when declined or failed.
setup_store() {
  local -a keys=()
  local line n i choice fpr="" me name before
  if [ -z "$GPG_BIN" ]; then
    warn "no gpg on your PATH, so no pass store can be made"
    return 1
  fi
  # pinentry asks for the GnuPG passphrase on this terminal.
  GPG_TTY="$(tty)" && export GPG_TTY
  echo "  keyswitch keeps your keys encrypted in a pass store, $KS_STORE,"
  echo "  and you do not have one yet. pass encrypts with a GnuPG key."
  while IFS= read -r line; do keys+=("$line"); done < <(gpg_secret_keys)
  n=${#keys[@]}
  if [ "$n" -eq 0 ]; then
    me="$(id -un)"
    name="$(getent passwd "$me" 2>/dev/null | cut -d: -f5 | cut -d, -f1 | tr -d '<>')" || name=""
    [ -n "$name" ] || name="$me"
    echo "  You have no GnuPG key. GnuPG can make one now; it asks for a passphrase,"
    echo "  which you will type again whenever keyswitch switches keys."
    ask_yes "Create a GnuPG key for \"$name <$me@slac.stanford.edu>\"?" || return 1
    before="$(gpg_secret_keys | cut -f1)"
    # --yes answers GnuPG's own "Continue?"; the passphrase still comes from pinentry.
    "$GPG_BIN" --yes --quick-generate-key "$name <$me@slac.stanford.edu>" \
        default default never \
      || { warn "GnuPG could not create the key"; return 1; }
    fpr="$(gpg_secret_keys | cut -f1 | grep -vxF "$before" | head -n 1 || true)"
    [ -n "$fpr" ] || { warn "cannot find the GnuPG key just made"; return 1; }
  elif [ "$n" -eq 1 ]; then
    fpr="${keys[0]%%$'\t'*}"
    ask_yes "Make it with your GnuPG key ${keys[0]#*$'\t'} ($fpr)?" || return 1
  else
    echo "  Your GnuPG keys:"
    for i in "${!keys[@]}"; do
      printf '    %d) %s  %s\n' $((i + 1)) "${keys[$i]#*$'\t'}" "${keys[$i]%%$'\t'*}"
    done
    while :; do
      choice=""
      IFS= read -r -p "  Which one should encrypt your pass store? [1-$n, Enter = 1, n = none] " choice \
        || choice=n
      case "$choice" in
        '') choice=1 ;;
        [Nn]|[Nn][Oo]) return 1 ;;
      esac
      if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$n" ]; then
        break
      fi
      echo "  Please answer a number from 1 to $n, or n."
    done
    fpr="${keys[$((choice - 1))]%%$'\t'*}"
  fi
  PASSWORD_STORE_DIR="$KS_STORE" "$PASS_BIN" init "$fpr" 2>&1 | sed 's/^/      /' || true
  if [ ! -f "$KS_STORE/.gpg-id" ]; then
    warn "pass init did not set up $KS_STORE"
    return 1
  fi
  ok "pass store ready: $KS_STORE"
}

# With a store (rule 4 above). Sets KEY_IN_USE. Returns 1 when key.dat may not
# hold what was chosen, and the caller then writes it directly.
register_keys() {
  if [ -n "$TYPED_KEY" ]; then
    ks_add shared "$SHARED_KEY" --force \
      || warn "could not register the shared key (see above); going on with yours"
    ks_add personal "$TYPED_KEY" --force --use || return 1
    KEY_IN_USE=personal
    return 0
  fi
  if [ -n "$CURRENT_NAME" ] && [ "$CURRENT_NAME" != shared ]; then
    ks_add shared "$SHARED_KEY" --force \
      || warn "could not register the shared key (see above)"
    KEY_IN_USE="$CURRENT_NAME"
    ok "kept your current key '$CURRENT_NAME'"
    return 0
  fi
  if [ -z "$CURRENT_NAME" ] && [ "$OWN_KEY_STATE" != none ] && [ "$OWN_KEY_STATE" != rejected ]; then
    # key.dat holds a key keyswitch does not know -- pasted on an earlier run
    # that had no store, say. Adopt it rather than overwrite it.
    ks_add shared "$SHARED_KEY" --force \
      || warn "could not register the shared key (see above)"
    if [ ! -e "$KS_STORE/$KS_SERVICE/personal.gpg" ]; then
      ks_add personal "$EXISTING_KEY" --use || return 1
      ok "stored the key already in $USER_KEY_FILE as $KS_SERVICE/personal"
      KEY_IN_USE=personal
    else
      warn "$USER_KEY_FILE holds a key keyswitch does not know, and $KS_SERVICE/personal"
      warn "exists already; left both alone. To store that key under a new name:"
      warn "    $KEYSWITCH_BIN -s $KS_SERVICE add NAME --use < $USER_KEY_FILE"
      KEY_IN_USE="the key already in $USER_KEY_FILE"
    fi
    return 0
  fi
  ks_add shared "$SHARED_KEY" --force --use || return 1
  KEY_IN_USE=shared
}

OWN_PASS="$(type -P pass 2>/dev/null || true)"
PASS_BIN="${OWN_PASS:-$SHARED_PASS}"
GPG_BIN="$(type -P gpg2 2>/dev/null || type -P gpg 2>/dev/null || true)"
KS_OK=0
[ -x "$KEYSWITCH_BIN" ] && KS_OK=1

# What is in use now. `keyswitch current` never decrypts anything.
CURRENT_NAME=""
if [ "$KS_OK" = 1 ]; then
  CURRENT_NAME="$("$KEYSWITCH_BIN" -s "$KS_SERVICE" current 2>/dev/null)" || CURRENT_NAME=""
fi
EXISTING_KEY=""
if [ -f "$USER_KEY_FILE" ] && [ -r "$USER_KEY_FILE" ]; then
  IFS= read -r EXISTING_KEY < "$USER_KEY_FILE" || true
  EXISTING_KEY="${EXISTING_KEY%$'\r'}"
fi
# A key in key.dat that is not the shared one was chosen by its owner, so it
# is kept unless the gateway says it no longer works.
OWN_KEY_STATE=none   # none | accepted | rejected | unchecked
if [ -n "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != "$SHARED_KEY" ]; then
  _rc=0
  check_key "$EXISTING_KEY" || _rc=$?
  case $_rc in
    0) OWN_KEY_STATE=accepted ;;
    1) OWN_KEY_STATE=rejected ;;
    *) OWN_KEY_STATE=unchecked ;;
  esac
fi
if [ -n "$CURRENT_NAME" ]; then
  ok "key in use now: '$CURRENT_NAME' (keyswitch)"
fi

# What pressing Enter at the prompt keeps.
if [ -n "$CURRENT_NAME" ] && [ "$CURRENT_NAME" != shared ]; then
  ENTER_DOES="keep your current key '$CURRENT_NAME'"
  if [ "$OWN_KEY_STATE" = rejected ]; then
    warn "the gateway rejects your current key '$CURRENT_NAME'. Switch with:"
    warn "    $KEYSWITCH_BIN -s $KS_SERVICE use shared"
  fi
elif [ -z "$CURRENT_NAME" ] && [ "$OWN_KEY_STATE" != none ] && [ "$OWN_KEY_STATE" != rejected ]; then
  ENTER_DOES="keep the key already in $USER_KEY_FILE"
else
  ENTER_DOES="use the shared LCLS key"
fi

INTERACTIVE=0
if [ "$DRY_RUN" != 1 ] && [ -t 0 ]; then INTERACTIVE=1; fi

# 1. Ask. The answer is read hidden, checked, and only then accepted.
TYPED_KEY=""
if [ "$INTERACTIVE" = 1 ]; then
  echo "  If you have a personal SLAC AI key, paste it here; it is not shown."
  while :; do
    _in=""
    IFS= read -r -s -p "  Paste your personal SLAC AI key, or press Enter to $ENTER_DOES: " _in \
      || _in=""
    echo >&2
    _in="${_in#"${_in%%[![:space:]]*}"}"
    _in="${_in%"${_in##*[![:space:]]}"}"
    [ -n "$_in" ] || break
    _rc=0
    check_key "$_in" || _rc=$?
    case $_rc in
      0) TYPED_KEY="$_in"; ok "the gateway accepted that key"; break ;;
      1) warn "the gateway rejected that key. Paste it again, or press Enter to $ENTER_DOES." ;;
      *) warn "could not check that key with $BASE_URL. Paste it again, or press Enter to $ENTER_DOES." ;;
    esac
  done
  _in=""
  if [ -n "$TYPED_KEY" ] && [ "$TYPED_KEY" = "$SHARED_KEY" ]; then
    warn "that is the shared LCLS key, not a personal one; storing it as $KS_SERVICE/personal anyway"
  fi
elif [ "$DRY_RUN" = 1 ]; then
  echo "  (dry-run) would not ask for a personal key; a real run in a terminal does"
fi

# 2. keyswitch's settings.
KS_CONFIG_OK=0
if [ "$DRY_RUN" = 1 ]; then
  if [ -n "$OWN_PASS" ]; then _p="your own pass ($OWN_PASS) stays in charge"
  else _p="pass = $SHARED_PASS, unless a pass line is there"; fi
  echo "  (dry-run) would merge into $KS_DIR/config: trusted_dirs $KS_TRUSTED_DIRS; $_p"
  echo "  (dry-run) would write $KS_DIR/$KS_SERVICE.conf:"
  ks_service_content | sed 's/^/      /'
elif write_ks_config; then
  KS_CONFIG_OK=1
else
  warn "could not write keyswitch's settings in $KS_DIR"
fi

# 3. The pass store.
HAVE_STORE=0
[ -f "$KS_STORE/.gpg-id" ] && HAVE_STORE=1
if [ "$KS_OK" = 0 ]; then
  warn "keyswitch is not installed at $KEYSWITCH_BIN"
elif [ "$HAVE_STORE" = 1 ]; then
  ok "pass store: $KS_STORE"
elif [ "$DRY_RUN" = 1 ]; then
  echo "  (dry-run) no pass store at $KS_STORE; a real run in a terminal offers to make one"
elif [ "$INTERACTIVE" = 1 ] && [ "$KS_CONFIG_OK" = 1 ]; then
  if setup_store; then HAVE_STORE=1; fi
fi

# 4. and 5. Register with keyswitch, or write key.dat directly.
KEY_IN_USE=""
VIA_KS=0
if [ "$DRY_RUN" = 1 ]; then
  if [ "$KS_OK" = 1 ] && [ "$HAVE_STORE" = 1 ]; then
    if [ -n "$CURRENT_NAME" ] && [ "$CURRENT_NAME" != shared ]; then
      echo "  (dry-run) would store the shared key as $KS_SERVICE/shared and keep '$CURRENT_NAME' in use"
    elif [ -z "$CURRENT_NAME" ] && [ "$OWN_KEY_STATE" != none ] && [ "$OWN_KEY_STATE" != rejected ]; then
      echo "  (dry-run) would store the shared key as $KS_SERVICE/shared, and the key in $USER_KEY_FILE as $KS_SERVICE/personal (in use)"
    else
      echo "  (dry-run) would store the shared key as $KS_SERVICE/shared and put it in use: $USER_KEY_FILE"
    fi
  elif [ "$CURRENT_NAME" != shared ] && [ "$OWN_KEY_STATE" != none ] && [ "$OWN_KEY_STATE" != rejected ]; then
    echo "  (dry-run) would keep the key already in $USER_KEY_FILE"
  else
    echo "  (dry-run) would write the shared key to $USER_KEY_FILE (mode 600)"
  fi
else
  if [ "$KS_OK" = 1 ] && [ "$KS_CONFIG_OK" = 1 ] && [ "$HAVE_STORE" = 1 ]; then
    if register_keys; then
      VIA_KS=1
    else
      warn "keyswitch could not store your keys (see above), so $USER_KEY_FILE is written directly."
      warn "re-run this installer to try again."
    fi
  elif [ "$KS_OK" = 1 ]; then
    warn "keyswitch could not be set up: there is no pass store at $KS_STORE."
    if [ "$INTERACTIVE" = 1 ]; then
      warn "re-run this installer to try again."
    else
      warn "re-run this installer in a terminal and it will offer to make one."
    fi
  fi
  if [ "$VIA_KS" = 0 ]; then
    if [ -n "$TYPED_KEY" ]; then
      write_user_key "$TYPED_KEY" || die "cannot write $USER_KEY_FILE"
      ok "wrote your personal key to $USER_KEY_FILE (mode 600)"
      KEY_IN_USE="your personal key"
    elif [ "$CURRENT_NAME" != shared ] && [ "$OWN_KEY_STATE" != none ] && [ "$OWN_KEY_STATE" != rejected ]; then
      chmod 600 "$USER_KEY_FILE"
      if [ "$OWN_KEY_STATE" = unchecked ]; then
        warn "could not check the key in $USER_KEY_FILE with the gateway; kept it"
      fi
      KEY_IN_USE="the key already in $USER_KEY_FILE"
    else
      if [ "$OWN_KEY_STATE" = rejected ]; then
        warn "the gateway rejects the key in $USER_KEY_FILE; replacing it with the shared key"
      fi
      write_user_key "$SHARED_KEY" || die "cannot write $USER_KEY_FILE"
      ok "wrote the shared key to $USER_KEY_FILE (mode 600)"
      KEY_IN_USE=shared
    fi
  fi
fi
TYPED_KEY=""
EXISTING_KEY=""

if [ "$DRY_RUN" != 1 ]; then
  if [ "$KEY_IN_USE" = shared ]; then
    ok "$FUNC_NAME will use the shared LCLS key"
  elif [ "$VIA_KS" = 1 ] && [[ $KEY_IN_USE != *' '* ]]; then
    # A keyswitch name (they have no spaces), not a description.
    ok "$FUNC_NAME will use your key '$KEY_IN_USE'"
  else
    ok "$FUNC_NAME will use $KEY_IN_USE"
  fi
  if [ "$VIA_KS" = 1 ]; then
    ok "your keys: $KEYSWITCH_BIN -s $KS_SERVICE list"
  fi
  if [ "$KEY_IN_USE" = shared ]; then
    echo
    warn "you are on the SHARED LCLS key. About 30 people use it, with one monthly"
    warn "budget between them, and SLAC IT plans to retire it."
    if [ "$VIA_KS" = 1 ]; then
      warn "when you have a personal SLAC AI key, store it and use it with:"
      warn "    $KEYSWITCH_BIN -s $KS_SERVICE add personal --use"
      warn "(in a new shell, plain 'keyswitch -s $KS_SERVICE add personal --use' works too)"
    else
      warn "when you have a personal SLAC AI key, re-run this installer in a"
      warn "terminal and paste it when asked."
    fi
  fi
fi

# ─── Write the config dir ─────────────────────────────────────────────────
step "Config dir: $LCLS_DIR"

# Two kinds of key live in this file and it is worth keeping them apart.
#
# REQUIRED. apiKeyHelper and env.ANTHROPIC_BASE_URL are what make claude-lcls
# work at all; apiKeyHelper alone sends the SLAC key to api.anthropic.com and
# comes back 401.
#
# apiKeyHelper reads YOUR key file, $USER_KEY_FILE, which the "API key" step
# above filled (keyswitch, or the installer itself without a store). Until
# 2026-10 it read the shared slac-key.dat in place; the merge below makes the
# template's value win, so an existing user moves over on their next re-run.
# The path is ABSOLUTE, expanded here at install time. Cogito sessions see
# ~/.config through a symlink, so the same absolute path works there too.
# Claude Code calls apiKeyHelper again after 5 minutes or on a 401 (its
# documented default; not measured here), which is how `keyswitch use`
# reaches sessions that are already open.
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
# THE opus ALIAS IS ALSO THE DEFAULT MODEL. With no `model` key in settings.json
# (this template deliberately writes none), plain `claude-lcls`, `--model opus`
# and `--model default` all resolved to the opus alias on 2.1.285 -- measured
# 2026-10-13. So the line below decides what every user gets by default.
#
# OPUS 5.5 IS THE opus ALIAS since 2026-10-13, the day a ttl "1h" request for
# it first landed in ephemeral_1h (see PROMPT CACHE TTL below). It was opt-in
# from 2026-10-07 until then. Opus 5 stays reachable with
# `claude-lcls --model "us.anthropic.claude-opus-5[1m]"`, and a user who wants it
# as their own default can set "model" to that id here: the installer's merge
# keeps a key the template does not define. Opus 5.5 needs 2.1.285+: 2.1.267 has
# zero occurrences of "opus-5-5", and while it still answers, it logs
# [claude-code:unrecognized_model], caps output at 32000 instead of 128000 and
# prices the session at Opus 5 rates. 2.1.285 reports 1000000 / 128000 with or
# without [1m]; keep the suffix so a rollback to 2.1.267 keeps the 1M window.
# Measured 2026-10-07.
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
# OPUS 5.5 WAS THE EXCEPTION, and is not any more. From 2026-10-07 to at least
# 2026-10-08 the gateway cached it for 5 minutes only: a raw request with
# cache_control ttl "1h" landed in ephemeral_5m for opus-5-5 and in ephemeral_1h
# for sonnet-5, with or without the extended-cache-ttl beta, so the cause was
# gateway-side. On 2026-10-13 the same request, byte for byte, landed in
# ephemeral_1h for opus-5-5 too, and so did claude-lcls with promptCacheTtl
# alone -- ENABLE_PROMPT_CACHING_1H is not needed. That is what moved the opus
# alias. If the 5-minute cache comes back, moving the alias back to
# us.anthropic.claude-opus-5[1m] is a one-line change to the env block below.
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
# The pin moved again, to 2.1.285, on 2026-10-07 so that Opus 5.5 gets the
# full 128k output and correct pricing. A string scan
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

  "apiKeyHelper": "cat $USER_KEY_FILE",

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
  ok "no key is stored here — apiKeyHelper reads it from $USER_KEY_FILE at runtime"
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
# keyswitch: which of your keys (pass entries under $KS_SERVICE/) $FUNC_NAME reads
# from $USER_KEY_FILE. Try: keyswitch -s $KS_SERVICE list
keyswitch() {
    if [ ! -x "$KEYSWITCH_BIN" ]; then
        echo "keyswitch: the shared keyswitch is not runnable: $KEYSWITCH_BIN" >&2
        return 127
    fi
    "$KEYSWITCH_BIN" "\$@"
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
  echo "    keyswitch -s $KS_SERVICE list        # your keys; * = the one in use"
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
  echo "   2. Auth errors: confirm the key in $USER_KEY_FILE still works," >&2
  echo "      independent of Claude Code (the key reaches curl on stdin, never on" >&2
  echo "      its command line, where 'ps' would show it to everyone):" >&2
  echo "        sed -n '1s/^/x-api-key: /p' $USER_KEY_FILE \\" >&2
  echo "          | curl -q -s -o /dev/null -w '%{http_code}\\n' -H @- $BASE_URL/v1/models" >&2
  echo "      200 = fine. 000 = off the SLAC network/VPN. 401/403 = key problem." >&2
  echo "      Which key that is:  $KEYSWITCH_BIN -s $KS_SERVICE current" >&2
  echo >&2
  echo "   3. Model errors naming an id without the 'us.anthropic.' prefix mean an" >&2
  echo "      ANTHROPIC_DEFAULT_*_MODEL entry is missing from" >&2
  echo "      $LCLS_DIR/settings.json — all three are required." >&2
  echo >&2
  echo "  Your own ~/.claude/ and ~/.claude.json were not touched either way." >&2
  echo "  Remove this install with: $0 --uninstall" >&2
  exit 1
fi
