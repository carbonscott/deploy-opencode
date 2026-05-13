#!/usr/bin/env bash
# Meta-deploy script for externalized skills.
# Reads skills.manifest.yml; clones each repo; rsyncs opencode/skills/<name>/
# and tools/<X>/ into the shared deploy dir; fixes permissions.
#
# Usage:
#   ./deploy.sh                      # deploy all skills in manifest
#   ./deploy.sh ask-epics cuda-docs  # deploy specific skills only
#   DRY_RUN=1 ./deploy.sh            # show what would change, no writes
#
# See handoff/skill-externalize-guide.md for layout and conventions.
# Cron entries are NOT auto-installed — install them manually on sdfcron001
# per the `cron:` block in the manifest.

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────
DEPLOY_ROOT="${DEPLOY_ROOT:-/sdf/group/lcls/ds/dm/apps/dev}"
SKILLS_DST="$DEPLOY_ROOT/opencode/skills"
AGENTS_DST="$DEPLOY_ROOT/opencode/agents"
TOOLS_DST="$DEPLOY_ROOT/tools"

STAGING_ROOT="${STAGING_ROOT:-/tmp/skill-deploy-$USER}"
MANIFEST="${MANIFEST:-$(cd "$(dirname "$0")" && pwd)/skills.manifest.json}"
DRY_RUN="${DRY_RUN:-0}"
GROUP="${PS_DATA_GROUP:-ps-data}"

mkdir -p "$STAGING_ROOT"

# ─── Manifest parse via jq ────────────────────────────────────────────────
# Emits one TSV row per skill: name<TAB>repo<TAB>ref<TAB>has_cron(0|1)
parse_manifest() {
  jq -r '.skills[] | [.name, .repo, (.ref // "main"), (if .cron then 1 else 0 end)] | @tsv' "$MANIFEST"
}

# ─── Rsync + permissions wrapper ──────────────────────────────────────────
rsync_and_chmod() {
  local src="$1"
  local dst="$2"
  local opts=(-a --delete)
  [ "$DRY_RUN" = "1" ] && opts+=(--dry-run -v)

  mkdir -p "$dst"
  rsync "${opts[@]}" "$src" "$dst"

  if [ "$DRY_RUN" != "1" ]; then
    chgrp -R "$GROUP" "$dst" || echo "WARN: chgrp $GROUP failed on $dst"
    chmod -R g+rX "$dst" || echo "WARN: chmod g+rX failed on $dst"
  fi
}

# ─── Per-skill deploy ─────────────────────────────────────────────────────
deploy_skill() {
  local name="$1"
  local repo="$2"
  local ref="$3"
  local stage="$STAGING_ROOT/$name"

  echo "── $name ($repo @ $ref)"

  # Clone or update
  if [ -d "$stage/.git" ]; then
    git -C "$stage" fetch --depth=1 origin "$ref"
    git -C "$stage" checkout "$ref"
    git -C "$stage" reset --hard "origin/$ref" 2>/dev/null || true
  else
    rm -rf "$stage"
    git clone --depth=1 -b "$ref" "git@github.com:$repo.git" "$stage"
  fi

  # opencode/skills/<name>/
  local src="$stage/opencode/skills/$name/"
  if [ ! -d "$src" ]; then
    echo "  WARN: $src not present in $repo; skipping skill content"
  else
    rsync_and_chmod "$src" "$SKILLS_DST/$name/"
    echo "  ✓ skill content"
  fi

  # agents/<name> → ../skills/<name>
  local agent_link="$AGENTS_DST/$name"
  if [ "$DRY_RUN" != "1" ]; then
    if [ ! -e "$agent_link" ] && [ ! -L "$agent_link" ]; then
      ln -s "../skills/$name" "$agent_link"
      echo "  ✓ agents/ symlink created"
    fi
  else
    [ ! -e "$agent_link" ] && [ ! -L "$agent_link" ] && echo "  (dry-run) would create $agent_link"
  fi

  # tools/<X>/ (any number of subdirs)
  if [ -d "$stage/tools" ]; then
    for tools_dir in "$stage/tools"/*/; do
      [ -d "$tools_dir" ] || continue
      local tname
      tname=$(basename "$tools_dir")
      rsync_and_chmod "$tools_dir" "$TOOLS_DST/$tname/"
      echo "  ✓ tools/$tname"
    done
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────
main() {
  if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest not found: $MANIFEST" >&2
    exit 1
  fi

  local -a wanted=("$@")
  local rows
  rows=$(parse_manifest)

  while IFS=$'\t' read -r name repo ref has_cron; do
    if [ ${#wanted[@]} -gt 0 ]; then
      local match=0
      for w in "${wanted[@]}"; do
        [ "$w" = "$name" ] && match=1 && break
      done
      [ "$match" = "0" ] && continue
    fi
    deploy_skill "$name" "$repo" "$ref"
  done <<< "$rows"

  echo
  echo "Done. Cron entries are not auto-installed — install manually on sdfcron001"
  echo "per the 'cron:' blocks in $MANIFEST."
}

main "$@"
