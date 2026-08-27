#!/usr/bin/env bash
# Install `claude-lcls` — Claude Code pointed at the SLAC AI Gateway.
#
# Gives you a `claude-lcls` command that runs Claude Code against
# https://ai-api.slac.stanford.edu using the shared team key, WITHOUT touching
# your existing `claude` setup (personal subscription, API key, whatever you
# already have). The two live side by side:
#
#     claude        -> your existing config, untouched
#     claude-lcls   -> SLAC gateway, team key, this config
#
# Usage:
#   ./install-claude-lcls.sh              # install (safe to re-run)
#   ./install-claude-lcls.sh --uninstall  # remove it again
#   ./install-claude-lcls.sh --dry-run    # show what would happen, write nothing
#
# Requirements: membership in `ps-users`, the `claude` binary on PATH, and the
# SLAC network or VPN. The script checks all three before writing anything.
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

MARK_BEGIN="# >>> claude-lcls >>>"
MARK_END="# <<< claude-lcls <<<"

ok()   { echo "  ✓ $*"; }
warn() { echo "  WARN: $*" >&2; }
die()  { echo "  ✗ $*" >&2; exit 1; }
step() { echo; echo "── $*"; }

# Marker matching is normalised: trailing whitespace and carriage returns are
# stripped before comparing, so a CRLF rc or a marker line with a stray trailing
# space is still recognised. EVERY marker test below goes through one of these
# three helpers, so grep-style and awk-style matching can never drift apart.

# stdout = $1 with only COMPLETE marker blocks removed. An UNTERMINATED block
# (begin marker, no end marker) is held back and re-emitted verbatim, so a
# hand-edited or half-written rc never loses everything below the marker.
strip_block() {
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    { line = $0; sub(/[ \t\r]+$/, "", line) }
    line == b && !inblk { inblk = 1; hold = $0 ORS; next }
    inblk && line == e  { inblk = 0; hold = "";      next }
    inblk               { hold = hold $0 ORS;        next }
                        { print }
    END                 { if (inblk) printf "%s", hold }
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

# strip_block $1 back into place, PRESERVING mode and ownership. The GNU
# `sed -i` this replaced kept the mode; a fresh temp file + mv would silently
# widen a 600 rc to whatever the umask says.
rewrite_stripped() {
  local rc="$1" tmp="$1.tmp.$$"
  strip_block "$rc" > "$tmp"
  chmod --reference="$rc" "$tmp" 2>/dev/null || chmod "$(stat -c %a "$rc")" "$tmp"
  chown --reference="$rc" "$tmp" 2>/dev/null || true
  mv "$tmp" "$rc"
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

MODE=install
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE=uninstall ;;
    --dry-run)   DRY_RUN=1 ;;
    -h|--help)   sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  echo "Config dir left in place: $LCLS_DIR"
  echo "Remove it yourself if you want it gone:  rm -rf $LCLS_DIR"
  echo "Your own ~/.claude/ was never touched."
  exit 0
fi

# ─── Preflight ────────────────────────────────────────────────────────────
step "Preflight"

if ! command -v claude >/dev/null 2>&1; then
  if [ -n "$(ls -A "$HOME/.local/share/claude/versions" 2>/dev/null)" ]; then
    echo "  ✗ no 'claude' on PATH — but Claude Code IS installed here." >&2
    echo >&2
    echo "    Versioned binaries are present under" >&2
    echo "      $HOME/.local/share/claude/versions/" >&2
    echo "    What is missing is the launcher shim ~/.local/bin/claude that" >&2
    echo "    resolves them. The launcher reads \$HOME to find its versioned" >&2
    echo "    binary, so do NOT work around this by overriding HOME — restore" >&2
    echo "    the shim itself (a symlink to one of those versioned binaries, or" >&2
    echo "    the small resolver script), make sure ~/.local/bin is on PATH," >&2
    echo "    and re-run." >&2
    exit 1
  fi
  die "no 'claude' on PATH. Install Claude Code first, then re-run."
fi
CLAUDE_BIN="$(command -v claude)"
# A binary that exists and is executable but cannot RUN is a preflight failure,
# not a green checkmark with version "unknown".
CLAUDE_VER="$("$CLAUDE_BIN" --version 2>&1 | head -1)" \
  || die "'$CLAUDE_BIN' exists but failed to run: $CLAUDE_VER"
ok "claude found: $CLAUDE_BIN ($CLAUDE_VER)"

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
$FUNC_NAME() {
    CLAUDE_CONFIG_DIR="$LCLS_DIR" command claude "\$@"
}
$MARK_END
EOF

while IFS= read -r rc; do
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
done < <(rc_files)

if [ -n "$SKIPPED_RCS" ]; then
  echo
  warn "left untouched and still needing manual repair:$SKIPPED_RCS"
  warn "$FUNC_NAME was NOT installed into the file(s) above; repair the markers and re-run."
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
VERIFY_OUT="$(CLAUDE_CONFIG_DIR="$LCLS_DIR" command claude -p \
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
  echo "   1. 'No claude binary found in .../versions' means the launcher on PATH" >&2
  echo "      could not resolve its versioned binary under your \$HOME. Do NOT try" >&2
  echo "      to fix this by overriding HOME in the wrapper — the launcher reads" >&2
  echo "      \$HOME to find itself, so that breaks it. Reinstall Claude Code." >&2
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
