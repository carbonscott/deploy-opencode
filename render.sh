#!/usr/bin/env bash
# Render one single-source skill into per-harness trees.
#
# Metadata comes from the DEPLOYER via --meta <json-file>; when --meta is
# absent it falls back to an in-repo <source-dir>/skill.json. Exactly one of
# the two is read per run — they are never merged. Recognised fields: name,
# kind, slug, description_auto, description_menu, argument_hint,
# user_invocable. A 'source' key is accepted and IGNORED: it is meaningful to
# deploy.sh, which resolves it into the <source-dir> argument passed here.
#
# Reads <source-dir>/SKILL.md and writes the harness-specific layout under
# <output-dir>:
#
#   kind=skill    <out>/claude/skills/<slug>/SKILL.md   + assets
#                 <out>/opencode/skills/<slug>/SKILL.md + assets
#                 <out>/opencode/agents/<slug> -> ../skills/<slug>
#   kind=command  <out>/claude/commands/<slug>.md
#                 <out>/opencode/commands/<slug>.md     (no agents/ symlink)
#
# A leading YAML frontmatter block in the source SKILL.md is STRIPPED before
# the body is emitted, so the rendered file carries EXACTLY ONE block and it
# holds the deployer-supplied description. A native Claude Code SKILL.md can
# therefore be rendered with no content change to its repo.
#
# Assets = everything else in the source dir, EXCEPT skill.json, SKILL.md,
# .git/, tools/ (harness-neutral; deploy.sh ships it separately) and the
# build-output dirs /claude/, /opencode/ and /.rendered/ at the source root.
#
# Usage:
#   ./render.sh [--meta <json-file>] <source-dir> <output-dir>
#   ./render.sh --target claude   <source-dir> <output-dir>
#   ./render.sh --target opencode <source-dir> <output-dir>
#   DRY_RUN=1 ./render.sh <source-dir> <output-dir>
#   ./render.sh --check <source-dir> <tree-to-compare>
#
# bash + jq only, matching deploy.sh. See docs/design-single-source-skills.md
# and docs/design-manifest-harness.md.

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
CHECK=0
TARGETS="both"
META=""

usage() {
  sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --meta <json-file>               Read metadata from this JSON file instead of
                                   <source-dir>/skill.json. Same field names as
                                   a manifest 'harness' block. The two sources
                                   are never merged.
  --target <claude|opencode|both>  Which harness tree(s) to emit. Default: both.
  --check                          Write nothing. Render into a temp dir and
                                   diff it against the tree already sitting at
                                   <output-dir>, printing every difference.
                                   Exit 1 if anything differs. To check a
                                   deployed tree, point <output-dir> at the
                                   deploy root: the layout is the same, so
                                   --target opencode --check <src> \
                                   /sdf/group/lcls/ds/dm/apps/dev compares
                                   against opencode/skills/<slug>/.
  -h, --help                       This text.

Environment:
  DRY_RUN=1   Print what would be written; touch nothing.

Exit codes: 0 ok (and, under --check, no differences); 1 usage/validation
error, or a --check difference.
EOF
}

# ─── Argument parsing ─────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --meta) META="${2:-}"; shift 2 ;;
    --meta=*) META="${1#*=}"; shift ;;
    --target) TARGETS="${2:-}"; shift 2 ;;
    --target=*) TARGETS="${1#*=}"; shift ;;
    --check) CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) break ;;
  esac
done

if [ $# -ne 2 ]; then
  echo "ERROR: expected <source-dir> <output-dir>" >&2
  usage >&2
  exit 1
fi

SRC="${1%/}"
OUT="${2%/}"

case "$TARGETS" in
  claude|opencode) TARGET_LIST="$TARGETS" ;;
  both) TARGET_LIST="claude opencode" ;;
  *) echo "ERROR: --target must be claude, opencode or both (got '$TARGETS')" >&2; exit 1 ;;
esac

[ -d "$SRC" ] || { echo "ERROR: source dir not found: $SRC" >&2; exit 1; }
[ -f "$SRC/SKILL.md" ] || { echo "ERROR: $SRC/SKILL.md not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq not on PATH" >&2; exit 1; }

# ─── Metadata: --meta file, else in-repo skill.json ───────────────────────
# ONE source of truth per run. --meta wins outright: $SRC/skill.json is not
# read at all when --meta is given, and the two are never merged (merging would
# recreate the two-homes-for-one-fact problem the single-source design removes).
# Absent fields read back as the empty string. A 'source' key, if present, is
# ignored here — deploy.sh has already resolved it into $SRC.
META_SRC=""
if [ -n "$META" ]; then
  [ -f "$META" ] || { echo "ERROR: --meta file not found: $META" >&2; exit 1; }
  META_SRC="$META"
elif [ -f "$SRC/skill.json" ]; then
  META_SRC="$SRC/skill.json"
else
  echo "ERROR: no metadata for $SRC: pass --meta <json-file>, or provide" >&2
  echo "       $SRC/skill.json" >&2
  exit 1
fi

jq -e . "$META_SRC" >/dev/null 2>&1 || {
  echo "ERROR: $META_SRC is not valid JSON" >&2; exit 1; }

NAME="$(jq -r '.name // ""' "$META_SRC")"
# `kind` DEFAULTS TO "skill" when absent, deliberately (iteration 3, drift D3).
# This is not laxity, it is agreement with the validator: validate-manifest.sh
# guards its own kind check with `has("kind")`, so a harness block that simply
# OMITS kind is declared CLEAN by the validator. If render.sh hard-errored on
# that same input, the validator and the renderer would disagree about what a
# valid manifest is, and a deploy would die on a manifest the human had just
# been told was fine. The default keeps the two in step.
# Safety is NOT weakened. A kind that is present but WRONG still fails, in both
# places: the case statement below whitelists exactly skill|command and exits 1
# on anything else -- including "" and null, since `// "skill"` only substitutes
# for null/false and an explicit "" would fall through to the case and die.
# Do not "simplify" this to `// ""` without also removing the `has("kind")`
# guard in validate-manifest.sh; the two must change together or not at all.
KIND="$(jq -r '.kind // "skill"' "$META_SRC")"
SLUG="$(jq -r '.slug // .name // ""' "$META_SRC")"
DESC_AUTO="$(jq -r '.description_auto // ""' "$META_SRC")"
DESC_MENU="$(jq -r '.description_menu // ""' "$META_SRC")"
ARGHINT="$(jq -r '.argument_hint // ""' "$META_SRC")"
USERINV="$(jq -r 'if .user_invocable == true then "true" else "" end' "$META_SRC")"

[ -n "$NAME" ] || { echo "ERROR: $META_SRC: 'name' is required" >&2; exit 1; }
[ -n "$SLUG" ] || SLUG="$NAME"
[ -n "$DESC_AUTO" ] || { echo "ERROR: $META_SRC: 'description_auto' is required" >&2; exit 1; }
[ -n "$DESC_MENU" ] || { echo "ERROR: $META_SRC: 'description_menu' is required" >&2; exit 1; }
case "$KIND" in
  skill|command) ;;
  *) echo "ERROR: $META_SRC: 'kind' must be \"skill\" or \"command\" (got '$KIND')" >&2; exit 1 ;;
esac

# ─── Assets ───────────────────────────────────────────────────────────────
# Everything in the source dir except the control files, VCS metadata, and
# tools/. No per-skill exclusion lists: if a file is in the source dir it ships.
#
# tools/ is excluded by the layer line in docs/design-single-source-skills.md §2:
# a tools/<x>/ uv project is harness-NEUTRAL and deploy.sh rsyncs it to
# $DEPLOY_ROOT/tools/<x>/ on its own. In the single-source layout tools/ sits at
# the repo root, which IS the source dir, so without this exclusion every tools/
# project would also be copied into both harness skill trees — the exact
# duplication this design exists to remove.
#
# claude/, opencode/ and .rendered/ AT THE SOURCE ROOT are build outputs, never
# assets (design doc §3: they are gitignored generated trees). Excluding them is
# what makes rendering idempotent when <output-dir> is inside <source-dir> — the
# common in-place case, and the shape deploy.sh uses via $stage/.rendered.
# Without it the claude pass's output is picked up as an asset by the opencode
# pass and each further run nests one level deeper (12 copies of README.md after
# two runs, measured). It also stops a repo that still carries stale pre-migration
# claude//opencode/ trees from shipping them inside the rendered skill, and stops
# --check reporting a spurious "Only in <tmp>: .rendered" against a deploy staging
# dir. The three patterns are ANCHORED (leading /) so a legitimately-named
# subdirectory deeper in the tree — references/opencode/, say — still ships.
# .git/ and tools/ stay unanchored, unchanged from iterations 1-3: nested .git
# dirs are never assets at any depth, and anchoring tools/ would be a behaviour
# change outside this iteration's scope.
ASSET_EXCLUDES=(
  --exclude='skill.json' --exclude='SKILL.md'
  --exclude='.git/' --exclude='tools/'
  --exclude='/claude/' --exclude='/opencode/' --exclude='/.rendered/'
)

has_assets() {
  local f
  for f in "$SRC"/* "$SRC"/.[!.]*; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in
      skill.json|SKILL.md|.git|tools) continue ;;
      claude|opencode|.rendered) continue ;;
    esac
    return 0
  done
  return 1
}

# ─── Frontmatter stripping ────────────────────────────────────────────────
# A native Claude Code SKILL.md carries its own YAML frontmatter. render.sh
# emits exactly ONE block, built from the DEPLOYER's metadata, so a leading
# block in the source must be removed first.
#
# Leading block  = line 1 is exactly '---' (after an optional UTF-8 BOM and an
#                  optional trailing CR).
# Ends at        = the first LATER line that is exactly '---' or '...'.
# No block       = pass the file through byte-for-byte.
# Unterminated   = pass the file through byte-for-byte and WARN. Never eat the
#                  file: an empty body deploys an empty skill and nothing fails.
# A '---' horizontal rule later in the body is untouched: scanning stops at the
# closing marker and the rest is copied verbatim.
# Exactly one blank line after the closing marker is consumed, because
# emit_frontmatter already prints '---\n\n'. See docs/design-manifest-harness.md B2.
#
# fm_end <file> -> line number of the closing marker, or 0 if there is no
# terminated leading block. NOTE: awk's `exit` runs the END block, hence the
# `done` guard — without it END prints a second number.
fm_end() {
  awk '
    NR == 1 {
      l = $0
      sub(/^\357\273\277/, "", l)   # UTF-8 BOM, octal (portable; \x is gawk-only)
      sub(/\r$/, "", l)
      if (l != "---") { done = 1; print 0; exit }
      next
    }
    {
      l = $0
      sub(/\r$/, "", l)
      if (l == "---" || l == "...") { done = 1; print NR; exit }
    }
    END { if (!done) print 0 }
  ' "$1"
}

# strip_frontmatter <file> -> body on stdout
strip_frontmatter() {
  local f="$1" end first
  end="$(fm_end "$f")"
  if [ "$end" -gt 0 ]; then
    # Everything after the closing marker, minus at most one leading blank line.
    sed -n "$((end + 1)),\$p" "$f" \
      | awk 'NR == 1 { l = $0; sub(/\r$/, "", l); if (l == "") next } { print }'
    return 0
  fi
  first="$(head -n 1 "$f" | sed -e 's/^\xEF\xBB\xBF//' -e 's/\r$//')"
  if [ "$first" = "---" ]; then
    echo "  WARN: $f opens with '---' but the frontmatter block is never closed;" >&2
    echo "        passing the body through unstripped. The rendered file will" >&2
    echo "        carry TWO frontmatter blocks — fix the source." >&2
  fi
  cat "$f"
}

# ─── YAML scalar emission ─────────────────────────────────────────────────
# Emit a plain scalar when it is unambiguous, otherwise a double-quoted one.
# The quoting trigger set is deliberately conservative: ": ", " #", leading
# indicator characters, and leading/trailing whitespace.
yaml_scalar() {
  local v="$1"
  if [ -z "$v" ] \
     || [ "$v" != "${v#[ 	]}" ] || [ "$v" != "${v%[ 	]}" ] \
     || case "$v" in *": "*|*" #"*|\&*|\**|\!*|\%*|\@*|\`*|\'*|\"*|\[*|\{*|\>*|\|*|\#*|-\ *|\?*|:*) true ;; *) false ;; esac
  then
    # Escape backslashes then double quotes; no other escapes are needed for
    # the descriptions this repo carries (checked: no control chars).
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    printf '"%s"' "$v"
  else
    printf '%s' "$v"
  fi
}

# ─── Frontmatter per (kind, target) ───────────────────────────────────────
# Claude Code skills dispatch AUTOMATICALLY off `description`, so they get
# description_auto. opencode skills are picked from an @-menu, so they get
# description_menu. Commands are invoked explicitly in both harnesses; the
# text is a menu label there, but Claude Code also surfaces it in /help, so
# claude commands keep description_auto and opencode commands the menu text.
emit_frontmatter() {
  local target="$1"
  local desc
  case "$target" in
    claude) desc="$DESC_AUTO" ;;
    opencode) desc="$DESC_MENU" ;;
  esac

  printf -- '---\n'
  if [ "$KIND" = "skill" ]; then
    printf 'name: %s\n' "$(yaml_scalar "$NAME")"
    printf 'description: %s\n' "$(yaml_scalar "$desc")"
  else
    # Commands: no `name:` in Claude Code (the filename is the command).
    # Kept for opencode only when skill.json sets an explicit invocation name
    # that differs from the file slug.
    if [ "$NAME" != "$SLUG" ]; then
      printf 'name: %s\n' "$(yaml_scalar "$NAME")"
    fi
    printf 'description: %s\n' "$(yaml_scalar "$desc")"
    if [ "$USERINV" = "true" ]; then printf 'user-invocable: true\n'; fi
    if [ -n "$ARGHINT" ]; then printf 'argument-hint: %s\n' "$(yaml_scalar "$ARGHINT")"; fi
  fi
  printf -- '---\n\n'
}

# ─── Check mode ───────────────────────────────────────────────────────────
# Render into a temp dir and diff it against a tree that already exists — a
# deployed tree, or the output of an earlier render. Writes nothing under
# <output-dir>. Any difference sets CHECK_STATUS, which becomes the exit code.
CHECK_STATUS=0

check_target() {
  local target="$1"
  local dest="$2"
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-$SLUG-XXXXXX")"

  if [ "$KIND" = "command" ]; then
    { emit_frontmatter "$target"; strip_frontmatter "$SRC/SKILL.md"; } > "$tmp/rendered.md"
    if [ ! -f "$dest" ]; then
      echo "  ✗ MISSING $dest"
      CHECK_STATUS=1
    elif cmp -s "$tmp/rendered.md" "$dest"; then
      echo "  ✓ $dest matches"
    else
      echo "  ✗ DIFFERS $dest"
      diff -u "$dest" "$tmp/rendered.md" | sed 's/^/      /'
      CHECK_STATUS=1
    fi
    rm -rf "$tmp"
    return 0
  fi

  { emit_frontmatter "$target"; strip_frontmatter "$SRC/SKILL.md"; } > "$tmp/SKILL.md"
  rsync -a "${ASSET_EXCLUDES[@]}" "$SRC/" "$tmp/"
  if [ ! -d "$dest" ]; then
    echo "  ✗ MISSING $dest/"
    CHECK_STATUS=1
  elif diff -r "$tmp" "$dest" >/dev/null 2>&1; then
    echo "  ✓ $dest/ matches"
  else
    echo "  ✗ DIFFERS $dest/"
    diff -r "$tmp" "$dest" | sed 's/^/      /'
    CHECK_STATUS=1
  fi
  rm -rf "$tmp"
}

# ─── Render one target ────────────────────────────────────────────────────
# Builds into a staging dir and rsyncs with --delete so a second run over a
# populated output dir produces byte-identical results and no stale files.
render_target() {
  local target="$1"
  local dest stage

  if [ "$KIND" = "skill" ]; then
    dest="$OUT/$target/skills/$SLUG"
  else
    dest="$OUT/$target/commands/$SLUG.md"
    if has_assets; then
      echo "ERROR: kind=command has assets in $SRC, but neither harness loads" >&2
      echo "       files next to a command .md. Split them out or use kind=skill." >&2
      exit 1
    fi
  fi

  if [ "$CHECK" = "1" ]; then
    check_target "$target" "$dest"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "  (dry-run) would write $dest"
    if [ "$KIND" = "skill" ] && [ "$target" = "opencode" ]; then
      echo "  (dry-run) would link $OUT/opencode/agents/$SLUG -> ../skills/$SLUG"
    fi
    return 0
  fi

  if [ "$KIND" = "command" ]; then
    mkdir -p "$(dirname "$dest")"
    { emit_frontmatter "$target"; strip_frontmatter "$SRC/SKILL.md"; } > "$dest"
    echo "  ✓ $dest"
    return 0
  fi

  stage="$(mktemp -d "${TMPDIR:-/tmp}/render-$SLUG-XXXXXX")"

  { emit_frontmatter "$target"; strip_frontmatter "$SRC/SKILL.md"; } > "$stage/SKILL.md"
  rsync -a "${ASSET_EXCLUDES[@]}" "$SRC/" "$stage/"

  mkdir -p "$dest"
  rsync -a --delete "$stage/" "$dest/"
  rm -rf "$stage"
  echo "  ✓ $dest/"

  # opencode loads agents from agents/; a skill needs the symlink to be
  # @-invocable. Claude Code has no equivalent — skills/ is enough there.
  if [ "$target" = "opencode" ]; then
    local link="$OUT/opencode/agents/$SLUG"
    mkdir -p "$OUT/opencode/agents"
    if [ -L "$link" ]; then
      [ "$(readlink "$link")" = "../skills/$SLUG" ] || ln -sfn "../skills/$SLUG" "$link"
    elif [ -e "$link" ]; then
      echo "  WARN: $link exists and is not a symlink (not replaced)" >&2
      return 0
    else
      ln -s "../skills/$SLUG" "$link"
    fi
    echo "  ✓ $link -> ../skills/$SLUG"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────
if [ "$CHECK" = "1" ]; then
  echo "── $SLUG (kind=$KIND, name=$NAME) from $SRC — CHECK against $OUT"
else
  echo "── $SLUG (kind=$KIND, name=$NAME) from $SRC"
fi
for t in $TARGET_LIST; do
  render_target "$t"
done
exit "$CHECK_STATUS"
