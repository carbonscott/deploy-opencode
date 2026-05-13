#!/usr/bin/env bash
# Meta-deploy script for externalized skills.
# Reads skills.manifest.json; clones each repo; rsyncs opencode/skills/<name>/
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

# Persisted across runs so we don't re-clone 15 repos every deploy.
# Override STAGING_ROOT=... if /tmp gets wiped too aggressively.
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
# Usage: rsync_and_chmod <src> <dst> [extra_rsync_args...]
rsync_and_chmod() {
  local src="$1"
  local dst="$2"
  shift 2
  local opts=(-a --delete "$@")
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
    # Only reset when origin/$ref resolves (branches do; tags/SHAs under
    # --depth=1 do not). Silent || true would swallow real fetch failures.
    if git -C "$stage" rev-parse --verify "origin/$ref" >/dev/null 2>&1; then
      git -C "$stage" reset --hard "origin/$ref"
    fi
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
    elif [ -L "$agent_link" ]; then
      local current
      current=$(readlink "$agent_link")
      if [ "$current" != "../skills/$name" ]; then
        echo "  WARN: $agent_link points to '$current', expected '../skills/$name' (not auto-repaired)" >&2
      fi
    else
      echo "  WARN: $agent_link exists and is not a symlink (not auto-repaired)" >&2
    fi
  else
    if [ ! -e "$agent_link" ] && [ ! -L "$agent_link" ]; then
      echo "  (dry-run) would create $agent_link"
    elif [ -L "$agent_link" ]; then
      local current
      current=$(readlink "$agent_link")
      [ "$current" != "../skills/$name" ] && \
        echo "  (dry-run) WARN: $agent_link points to '$current', expected '../skills/$name'" >&2
    else
      echo "  (dry-run) WARN: $agent_link exists and is not a symlink" >&2
    fi
  fi

  # tools/<X>/ (any number of subdirs).
  # Exclude operator-local state files so re-deploy doesn't wipe them.
  if [ -d "$stage/tools" ]; then
    for tools_dir in "$stage/tools"/*/; do
      [ -d "$tools_dir" ] || continue
      local tname
      tname=$(basename "$tools_dir")
      rsync_and_chmod "$tools_dir" "$TOOLS_DST/$tname/" \
        --exclude='cron.log' --exclude='env.local' --exclude='*.log'
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
  local -a matched=()
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
    matched+=("$name")
    deploy_skill "$name" "$repo" "$ref"
  done <<< "$rows"

  # Warn if any requested skill name didn't match a manifest entry.
  if [ ${#wanted[@]} -gt 0 ]; then
    local -a missing=()
    for w in "${wanted[@]}"; do
      local found=0
      for m in "${matched[@]:-}"; do
        [ "$w" = "$m" ] && found=1 && break
      done
      [ "$found" = "0" ] && missing+=("$w")
    done
    if [ ${#missing[@]} -gt 0 ]; then
      echo "WARN: requested skill(s) not in manifest: ${missing[*]}" >&2
      exit 2
    fi
  fi

  echo
  echo "Done. Cron entries are not auto-installed — install manually on sdfcron001"
  echo "per the 'cron:' blocks in $MANIFEST."
}

main "$@"
