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

MODE=install
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE=uninstall ;;
    --dry-run)   DRY_RUN=1 ;;
    -h|--help)   sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "unknown argument: $arg (try --help)" ;;
  esac
done

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
    if grep -qF "$MARK_BEGIN" "$rc"; then
      if [ "$DRY_RUN" = 1 ]; then
        echo "  (dry-run) would strip the $FUNC_NAME block from $rc"
      else
        sed -i.claude-lcls-bak "/${MARK_BEGIN}/,/${MARK_END}/d" "$rc"
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
  echo "Config dir left in place: $LCLS_DIR"
  echo "Remove it yourself if you want it gone:  rm -rf $LCLS_DIR"
  echo "Your own ~/.claude/ was never touched."
  exit 0
fi

# ─── Preflight ────────────────────────────────────────────────────────────
step "Preflight"

command -v claude >/dev/null 2>&1 \
  || die "no 'claude' on PATH. Install Claude Code first, then re-run."
CLAUDE_BIN="$(command -v claude)"
CLAUDE_VER="$("$CLAUDE_BIN" --version 2>/dev/null | head -1 || echo 'unknown')"
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
HTTP_CODE="$(curl -s -o /dev/null -m 15 -w '%{http_code}' \
             -H "x-api-key: $(cat "$KEY_FILE")" \
             "$BASE_URL/v1/models" 2>/dev/null || echo 000)"
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

  linked=0
  for src in "$SKILLS_SRC"/*; do
    [ -e "$src" ] || continue
    linked=$((linked + 1))
    name="$(basename "$src")"
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
  if [ -f "$rc" ] && grep -qF "$MARK_BEGIN" "$rc"; then
    if [ "$DRY_RUN" = 1 ]; then
      echo "  (dry-run) would refresh the existing block in $rc"
    else
      sed -i.claude-lcls-bak "/${MARK_BEGIN}/,/${MARK_END}/d" "$rc"
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
