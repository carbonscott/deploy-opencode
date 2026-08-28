#!/usr/bin/env bash
# Meta-deploy script for externalized skills.
# Reads skills.manifest.json; clones each repo; renders each skill from the
# manifest's own metadata; rsyncs the result into the shared deploy dir; fixes
# permissions.
#
# Skill metadata lives in the MANIFEST, not in the repo. A manifest entry that
# carries a "harness" object is single-source: harness.source names the
# directory INSIDE the clone that holds SKILL.md plus its assets (for every
# repo today that is claude/skills/<name>, which is also the default when the
# field is absent), and harness.{kind,slug,description_auto,description_menu}
# supply everything render.sh needs. The external repo stays in native Claude
# Code shape: it needs no skill.json and no content change of any kind.
# deploy.sh writes the entry's harness block to a temp JSON file and hands it
# to `render.sh --meta`, and the rendered trees are what get deployed.
#
# A manifest entry with NO harness block is pre-migration and takes the
# original path unchanged: opencode only, from the repo's checked-in
# opencode/skills/<name>/, with nothing written to the claude tree. That is the
# rollback path for this design, so it still works — but it prints a
# DEPRECATED warning. A harness key that is PRESENT but MALFORMED is a hard
# ERROR, never a silent fall-back to legacy. An entry matching neither shape is
# an ERROR too, not a silent no-op.
#
# Usage:
#   ./deploy.sh                      # deploy all skills in manifest
#   ./deploy.sh ask-epics cuda-docs  # deploy specific skills only
#   DRY_RUN=1 ./deploy.sh            # show what would change, no writes
#   DEPLOY_CLAUDE=0 ./deploy.sh      # opencode tree only (see below)
#   MANIFEST=<path> ./deploy.sh      # deploy from an alternate manifest
#
# See docs/design-manifest-harness.md for the harness block's schema and
# handoff/skill-externalize-guide.md for layout and conventions.
# Cron entries are NOT auto-installed — install them manually on sdfcron001
# per the `cron:` block in the manifest.
#
# REF FORMS. A manifest entry's `ref` may be a BRANCH, a TAG, or a full
# 40-character lowercase hex commit SHA. Branch and tag refs take the original
# `git clone --depth=1 -b <ref>` path, unchanged. A SHA ref cannot: `clone -b`
# answers "Remote branch <sha> not found in upstream origin". It is instead
# fetched shallowly into a fresh repo (`git fetch --depth=1 origin <sha>`,
# served by GitHub's uploadpack.allowAnySHA1InWant — verified on this host
# against a non-tip commit) and checked out detached. Abbreviated SHAs are NOT
# supported; see is_sha_ref() for why. Pinning a ref to a SHA is how an entry
# is frozen to exactly the content that is already deployed live.
#
# CRON ps-data GUARD. Any entry with a non-null `cron` block has the cron
# script named by cron.script scanned BEFORE a single byte is written for that
# skill. A script that chgrps its data dir to ps-data when the live deployed
# copy reads ps-users is refused outright (DEPLOY_FAILED=1, nothing written),
# because deploying it would cut those corpora from 3748 ps-users readers to 61
# ps-data readers at the next cron tick. See assert_cron_group_safe(). There is
# deliberately NO environment override: a human must not be able to wave it
# through.

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────
DEPLOY_ROOT="${DEPLOY_ROOT:-/sdf/group/lcls/ds/dm/apps/dev}"
SKILLS_DST="$DEPLOY_ROOT/opencode/skills"
AGENTS_DST="$DEPLOY_ROOT/opencode/agents"
TOOLS_DST="$DEPLOY_ROOT/tools"

# Claude Code destinations. The opencode tree sits directly under $DEPLOY_ROOT
# (opencode/{skills,agents,commands}), so the claude tree goes alongside it at
# the same depth. Verified read-only on 2026-08-26: $DEPLOY_ROOT contains
# bin/ code/ data/ env/ opencode/ python/ software/ tools/ — nothing named
# claude/, so the name is free and the first real deploy creates it.
#
# NO agents/ equivalent on the claude side, deliberately. opencode's
# agents/<n> -> ../skills/<n> symlink exists so a skill is @-invocable; Claude
# Code has no such lookup and expects one .md file per subagent under agents/,
# so pointing that name at a skill directory would be wrong.
CLAUDE_SKILLS_DST="$DEPLOY_ROOT/claude/skills"
CLAUDE_CMDS_DST="$DEPLOY_ROOT/claude/commands"

# Persisted across runs so we don't re-clone 15 repos every deploy.
# Override STAGING_ROOT=... if /tmp gets wiped too aggressively.
STAGING_ROOT="${STAGING_ROOT:-/tmp/skill-deploy-$USER}"
MANIFEST="${MANIFEST:-$(cd "$(dirname "$0")" && pwd)/skills.manifest.json}"
RENDER="${RENDER:-$(cd "$(dirname "$0")" && pwd)/render.sh}"
DRY_RUN="${DRY_RUN:-0}"
GROUP="${PS_USERS_GROUP:-ps-users}"

# Default ON. NOTE (iteration 5): the old rationale — "the claude tree is
# written ONLY for migrated repos, so with zero external repos migrated today
# this flag changes nothing about what a real deploy produces" — is now FALSE.
# Every manifest entry carries a harness block, so every entry renders, so
# DEPLOY_CLAUDE=1 makes a full deploy create $DEPLOY_ROOT/claude/ and write ALL
# 17 skill directories plus their assets into it. The blast radius went from
# empty to the whole fleet in one step.
#
# The default is deliberately left at 1 — changing it is a human's call — but
# the consequences are now real, and they are: (a) ensure_claude_root() runs
# for real against the real deploy root for the first time, so a misfiring
# chgrp/chmod there is the 2026-02-12 incident class; (b) the claude tree is a
# second full copy of every skill and its assets; (c) the deployed claude-side
# `description:` becomes the manifest's harness.description_auto instead of the
# repo's own text. Recommended first live run: DEPLOY_CLAUDE=0, after a
# DEPLOY_CLAUDE=1 rehearsal against a mock DEPLOY_ROOT. DEPLOY_CLAUDE=0 is
# still the escape hatch for the pre-iteration-4 behaviour exactly.
DEPLOY_CLAUDE="${DEPLOY_CLAUDE:-1}"

# Set by deploy_skill() when a repo matches neither the single-source nor the
# legacy shape. main() turns it into a non-zero exit.
DEPLOY_FAILED=0

mkdir -p "$STAGING_ROOT"

# ─── Harness metadata temp files ──────────────────────────────────────────
# One normalised JSON object per skill, handed to render.sh via --meta. Kept in
# a single run-scoped dir so ONE trap cleans them all up: normal exit, the
# `exit 3` path at the end of main(), a `set -e` abort, and Ctrl-C alike. That
# is the chosen cleanup mechanism — a trap, not an rm at each return, because
# deploy_skill() has six early-return paths and an errexit abort has none.
# Under `set -euo pipefail` a failing mktemp aborts here, before any deploy
# work starts, which is what we want: no metadata dir, no deploy.
META_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deploy-harness-$USER-XXXXXX")"
trap 'rm -rf "$META_DIR"' EXIT INT TERM

# ─── Manifest parse via jq ────────────────────────────────────────────────
# Emits one TSV row per skill:
#   name<TAB>repo<TAB>ref<TAB>has_cron(0|1)<TAB>has_harness(0|1)<TAB>cron_script
# has_harness is the NEW column (iteration 5) and is the single-source-vs-legacy
# discriminator, replacing the old "is there a skill.json on disk" test. A JSON
# object cannot ride through @tsv, so only the boolean travels here; the block
# itself is fetched per-skill by write_harness_meta() below.
#
# The test is KEY PRESENCE (`has("harness")`), NOT `(.harness|type)=="object"`.
# That distinction is load-bearing: an entry whose harness is present but is a
# string/array/null must reach write_harness_meta() so it becomes a HARD ERROR.
# Typing the column as "is it an object" instead sent every malformed block
# quietly down the legacy branch — the exact "typo'd key silently reverts to
# legacy" hole this design closes. Only a FULLY ABSENT key means legacy.
# `has` on a non-object input would error, but .skills[] elements are objects.
#
# cron_script is the NEW column (iteration 4 of this campaign). It carries
# .cron.script — the repo-relative path of the cron script — or the empty
# string when .cron is null, which is what assert_cron_group_safe() keys off.
# The pre-existing has_cron boolean is left exactly where it is rather than
# repurposed, so nothing that already reads column 4 changes meaning.
parse_manifest() {
  jq -r '.skills[]
         | [ .name, .repo, (.ref // "main"),
             (if .cron then 1 else 0 end),
             (if has("harness") then 1 else 0 end),
             (.cron.script // "") ]
         | @tsv' "$MANIFEST"
}

# ─── Rsync + permissions wrapper ──────────────────────────────────────────
# Usage: rsync_and_chmod <src> <dst> [extra_rsync_args...]
rsync_and_chmod() {
  local src="$1"
  local dst="$2"
  shift 2
  local opts=(-a --delete "$@")

  # A dry run must write NOTHING, anywhere. The mkdir below used to run BEFORE
  # this check, so DRY_RUN=1 against a real deploy root created destination
  # directories for every skill — a "preview" with side effects. Return early.
  if [ "$DRY_RUN" = "1" ]; then
    opts+=(--dry-run -v)
    rsync "${opts[@]}" "$src" "$dst"
    return 0
  fi

  mkdir -p "$dst"
  rsync "${opts[@]}" "$src" "$dst"

  chgrp -R "$GROUP" "$dst" || echo "WARN: chgrp $GROUP failed on $dst"
  chmod -R g+rX "$dst" || echo "WARN: chmod g+rX failed on $dst"
  # chgrp CLEARS setgid on every directory it touches (docs/deploy-permissions.md
  # §3), which re-arms the 2026-02-12 incident: a file hand-dropped into a
  # deployed skill dir afterwards lands in the maintainer's primary group (gu)
  # instead of $GROUP. Re-assert it — step 2 of that incident's own checklist.
  # Must come AFTER chgrp, never before.
  find "$dst" -type d -exec chmod g+s {} + || \
    echo "WARN: chmod g+s failed on directories under $dst"
}

# ─── Single-file rsync + permissions wrapper ──────────────────────────────
# rsync_and_chmod is directory-oriented (mkdir -p "$dst", trailing slashes,
# --delete). A rendered command is one .md file, so it gets its own wrapper.
# No --delete: the destination is a single named file, not a tree.
# Usage: rsync_file_and_chmod <src-file> <dst-file>
rsync_file_and_chmod() {
  local src="$1"
  local dst="$2"
  local dstdir
  dstdir="$(dirname "$dst")"
  local opts=(-a)

  # Same dry-run-must-not-write rule as rsync_and_chmod above.
  if [ "$DRY_RUN" = "1" ]; then
    opts+=(--dry-run -v)
    rsync "${opts[@]}" "$src" "$dst"
    return 0
  fi

  mkdir -p "$dstdir"
  rsync "${opts[@]}" "$src" "$dst"

  chgrp "$GROUP" "$dstdir" "$dst" || echo "WARN: chgrp $GROUP failed on $dst"
  chmod g+rX "$dstdir" || echo "WARN: chmod g+rX failed on $dstdir"
  chmod g+r "$dst" || echo "WARN: chmod g+r failed on $dst"
  # Restore the setgid the chgrp above cleared. See rsync_and_chmod.
  chmod g+s "$dstdir" || echo "WARN: chmod g+s failed on $dstdir"
}

# ─── Claude tree roots ────────────────────────────────────────────────────
# $DEPLOY_ROOT/claude/ does not exist in production yet, so the first real
# deploy creates it. It must not be created with whatever group and mode
# mkdir happens to give it: $DEPLOY_ROOT itself is setgid ps-data
# (drwxrwsr-x psdatmgr ps-data, read 2026-08-26), so a bare mkdir would land
# the new tree in ps-data while the sibling opencode/ tree is ps-users.
# rsync_and_chmod only touches the per-skill subdirectory, so the two roots
# need this explicit pass. Called lazily — only when something is actually
# about to be written — so DEPLOY_CLAUDE=1 alone never creates an empty tree.
ensure_claude_root() {
  local d="$1"
  [ "$DRY_RUN" = "1" ] && return 0
  mkdir -p "$d"
  chgrp "$GROUP" "$DEPLOY_ROOT/claude" "$d" 2>/dev/null || \
    echo "WARN: chgrp $GROUP failed on $DEPLOY_ROOT/claude"
  # ABSOLUTE mode, not g+rX/g+s. docs/deploy-permissions.md §4 prescribes
  # 2750 / drwxr-s--- with other::--- , mirroring the sibling dev/opencode.
  # `chmod g+rX` only ever ADDS bits: under the real dev/ directory, whose
  # default ACL grants other::r-x, the freshly created root came out
  # drwxr-sr-x — world-traversable from day one, and `other::r-x` at the top
  # level is exactly what gates access (/sdf/group/lcls is world-rx all the
  # way down). 2750 sets the whole mode word in one call, so `other` is
  # cleared and setgid is asserted together.
  #
  # ORDERING TRAP (§3): chgrp CLEARS setgid, so this chmod must come AFTER the
  # chgrp above, never before. Do not reorder.
  chmod 2750 "$DEPLOY_ROOT/claude" "$d" 2>/dev/null || \
    echo "WARN: chmod 2750 failed on $DEPLOY_ROOT/claude"
}

# ─── Harness metadata + source-shape resolution ───────────────────────────
# Manifest-side, not filesystem-side. Before iteration 5 the discriminator was
# the PHYSICAL presence of a skill.json (<stage>/skill.json, then
# <stage>/src/<name>/skill.json, then any <stage>/src/*/skill.json whose .slug
# or .name matched). That required every external repo to carry harness-specific
# metadata. It is gone. Now: a manifest entry with a 'harness' block is
# single-source, and harness.source names the directory INSIDE the clone that
# holds SKILL.md and the assets, defaulting to claude/skills/<name>. The repo
# needs no skill.json and no content change of any kind.
#
# An entry with NO harness block takes the legacy path unchanged (see
# deploy_skill(); docs/design-manifest-harness.md §C2.1 — it is the rollback
# path for this campaign, so it must keep working).

# write_harness_meta <name> <meta-file>
# Validates the entry's harness block and writes the NORMALISED object — and
# nothing else — to <meta-file>, so its field names line up exactly with what
# `render.sh --meta` expects. Returns 1 (having printed an ERROR naming the
# entry) if the block is present but malformed; the caller must NOT fall back to
# the legacy branch on that, or a typo'd key silently reverts to legacy.
write_harness_meta() {
  local name="$1"
  local meta="$2"
  local reason

  # One jq pass produces a human-readable reason, or the empty string for OK.
  # Kept separate from the normalising pass below so the error message can name
  # the offending field instead of just "not a usable object".
  reason="$(jq -r --arg n "$name" '
      (.skills[] | select(.name == $n) | .harness) as $h
      | if ($h | type) != "object" then
          "harness is present but is a \($h | type), not a JSON object"
        elif ($h.kind | type) != "string" or $h.kind == "" then
          "harness.kind is missing or empty"
        elif $h.kind != "skill" and $h.kind != "command" then
          "harness.kind must be \"skill\" or \"command\" (got \($h.kind | tojson))"
        elif ($h | has("source")) and (($h.source | type) != "string" or $h.source == "") then
          "harness.source is present but empty or not a string"
        elif ($h.description_auto | type) != "string" or $h.description_auto == "" then
          "harness.description_auto is missing or empty"
        elif ($h.description_menu | type) != "string" or $h.description_menu == "" then
          "harness.description_menu is missing or empty"
        else "" end' "$MANIFEST")"

  if [ -n "$reason" ]; then
    echo "  ERROR: manifest entry '$name': $reason" >&2
    echo "         A malformed harness block is a hard error — deploy.sh will NOT" >&2
    echo "         fall back to the legacy layout. Run ./validate-manifest.sh." >&2
    return 1
  fi

  # jq -e exits 4 when the filter produces nothing, which under `set -e` would
  # abort the whole deploy. Wrapping it in `if` suspends errexit for the
  # condition, so a bad entry is a value, not a fatality.
  if jq -e --arg n "$name" '
        .skills[] | select(.name == $n) | .harness
        | select(type == "object")
        | { source:           ((.source // ("claude/skills/" + $n)) | sub("/+$"; "")),
            name:             (.name // $n),
            kind:             (.kind // "skill"),
            slug:             (.slug // .name // $n),
            description_auto: (.description_auto // ""),
            description_menu: (.description_menu // "") }
          + (if (.argument_hint // "") != "" then {argument_hint: .argument_hint} else {} end)
          + (if .user_invocable == true then {user_invocable: true} else {} end)
      ' "$MANIFEST" > "$meta"
  then
    :
  else
    rm -f "$meta"
    echo "  ERROR: manifest entry '$name' declares a 'harness' block that could not" >&2
    echo "         be normalised into a metadata object." >&2
    return 1
  fi
}

# resolve_harness_source <stage> <meta-file> -> prints the absolute source dir,
# returns 1 (having printed an ERROR) if it is unusable. A silent skip here
# would ship nothing and still exit 0 — exactly the bug class the iteration-4
# error branch was added to kill — so every failure is loud.
resolve_harness_source() {
  local stage="$1"
  local meta="$2"
  local rel dir

  rel="$(jq -r '.source' "$meta")"

  case "$rel" in
    ""|null) echo "  ERROR: harness.source is empty" >&2; return 1 ;;
    /*)      echo "  ERROR: harness.source must be repo-relative, got '$rel'" >&2; return 1 ;;
    ..|../*|*/../*|*/..)
             echo "  ERROR: harness.source must not contain '..', got '$rel'" >&2; return 1 ;;
  esac

  dir="$stage/$rel"
  if [ ! -d "$dir" ]; then
    echo "  ERROR: harness.source '$rel' is not a directory in this repo." >&2
    echo "         expected: $dir" >&2
    if [ -e "$dir" ]; then
      echo "         found:    a non-directory at that path" >&2
    else
      echo "         found:    nothing at that path; the clone's top level holds:" >&2
      ls -1 "$stage" 2>/dev/null | sed 's/^/                   /' >&2 || true
    fi
    return 1
  fi
  if [ ! -f "$dir/SKILL.md" ]; then
    echo "  ERROR: harness.source '$rel' has no SKILL.md." >&2
    echo "         expected: $dir/SKILL.md" >&2
    echo "         found:    $(ls -1 "$dir" 2>/dev/null | tr '\n' ' ')" >&2
    return 1
  fi
  echo "$dir"
}

# ─── Ref shape ────────────────────────────────────────────────────────────
# is_sha_ref <ref> -> 0 when <ref> is a FULL 40-character lowercase hex commit
# SHA, 1 otherwise (branch, tag, anything else).
#
# FULL LENGTH ONLY, on purpose, for two independent reasons:
#   1. An abbreviated SHA is indistinguishable from a legitimate ref name — a
#      branch or tag literally called "deadbeef" or "0123456" is legal git — so
#      treating short hex as a SHA would silently misroute real branches.
#   2. The server rejects it anyway. Verified on this host against GitHub:
#        git fetch --depth=1 origin 524de15
#        fatal: couldn't find remote ref 524de15
#      A protocol "want" line must carry a full object name; only the 40-char
#      form works.
# So an abbreviated SHA falls through to the branch path and fails loudly
# there, which is the right outcome: the fix is to pin the manifest to all 40
# characters. Uppercase hex is likewise treated as a ref name; git SHAs are
# canonically lowercase and the manifest is machine-written.
is_sha_ref() {
  case "$1" in
    *[!0-9a-f]*) return 1 ;;
    ????????????????????????????????????????) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Cron ps-data guard ───────────────────────────────────────────────────
# Five upstream repos (skill-ask-{epics,nersc,s3df,tiled,olcf}) ship a cron
# script whose corpus-publishing step reads
#     chgrp -R ps-data "$<X>_DOCS_DATA_DIR"
# while the LIVE deployed copy of that same script reads ps-users. The two
# groups are NOT nested: ps-users is gid 10000 with 3748 members, ps-data is
# gid 2279 with 61, and 3689 ps-users members are in neither. A bare deploy
# would overwrite the live script with the upstream one and the next cron tick
# — sdf-docs runs hourly, so under an hour — would chgrp the corpora down to 61
# readers. That is a silent availability regression, not a crash, so nothing
# downstream would catch it.
#
# The guard is MANIFEST-DRIVEN: it applies to every entry whose `cron` block is
# non-null and inspects exactly the script that block names. The 12 entries
# with cron: null are never inspected and behave precisely as they did before.
# That matters for correctness as well as scope — data/elog-copilot and the
# three elog tools directories are LEGITIMATELY ps-data and must stay that way,
# and elog-search has cron: null, so no path in this guard can ever look at
# them.
#
# There is NO escape hatch. No ALLOW_PS_DATA_CRON, no --force. The entire value
# of the check is that a human under deploy pressure cannot forget it, and an
# override flag is the thing that gets typed at exactly that moment.
#
# assert_cron_group_safe <name> <stage> <cron_script_relpath>
#   0 = safe, deploy may proceed.
#   1 = refuse this skill (caller sets DEPLOY_FAILED=1 and returns having
#       written nothing).
assert_cron_group_safe() {
  local name="$1"
  local stage="$2"
  local rel="$3"
  local f="$stage/$rel"

  # Same containment rules resolve_harness_source() applies: a manifest is an
  # input, and an absolute or ..-escaping cron.script would point the scan
  # outside the clone — at, for instance, the already-correct live copy.
  case "$rel" in
    /*)  echo "  ERROR: manifest entry '$name': cron.script must be repo-relative, got '$rel'" >&2
         return 1 ;;
    ..|../*|*/../*|*/..)
         echo "  ERROR: manifest entry '$name': cron.script must not contain '..', got '$rel'" >&2
         return 1 ;;
  esac

  # A missing cron script is an ERROR, not a warning. Two reasons: the manifest
  # and the repo disagree, which is a real defect either way; and more to the
  # point the guard cannot prove this skill is safe, and the whole design of
  # this check is fail-closed. Downgrading it to a warning would mean a single
  # upstream rename — moving the script to a path the manifest no longer names
  # — quietly disables the ps-data check for that skill while the tools/ rsync
  # still ships whatever script is actually in the repo.
  if [ ! -f "$f" ]; then
    echo "  ERROR: manifest entry '$name' declares cron.script '$rel', but the clone" >&2
    echo "         has no such file. Cannot verify the ps-data guard, so this skill" >&2
    echo "         is NOT deployed (fail-closed)." >&2
    echo "         expected: $f" >&2
    echo "         Fix: correct cron.script in $MANIFEST, or restore the script." >&2
    return 1
  fi

  # PATTERN. Match a chgrp COMMAND whose GROUP OPERAND is the literal ps-data:
  #   (^|[;&|(]|space)  the chgrp must start a command, so it is not matched
  #                     inside a longer word or a path such as .../my-chgrp-log
  #   chgrp
  #   ([[:space:]]+-...)*  any number of option words: -R, --recursive,
  #                     --reference=..., -h, and so on
  #   [[:space:]]+['"]?ps-data['"]?([[:space:]]|$)
  #                     the group operand, bare or quoted either way
  #
  # Neither too narrow nor too broad: it is broader than the literal known-bad
  # 'chgrp -R ps-data' because the option list and the quoting are free (an
  # upstream edit to `chgrp --recursive "ps-data"` would still be caught), and
  # it is narrower than a bare `grep ps-data` because the trailing delimiter
  # stops it matching ps-database, the command-start anchor stops it matching a
  # word or filename containing chgrp, and requiring ps-data in the group-
  # operand position means a comment, a log message, a variable named ps_data
  # or an unrelated mention of the group does not trip it.
  local ps_data_re
  ps_data_re="(^|[;&|(]|[[:space:]])chgrp([[:space:]]+-[^[:space:]]+)*[[:space:]]+['\"]?ps-data['\"]?([[:space:]]|\$)"
  # A chgrp whose group operand is an expansion — $G, ${G}, `...`, $(...) —
  # cannot be resolved by reading the file, so it is reported separately rather
  # than being silently treated as safe.
  local var_re
  var_re="(^|[;&|(]|[[:space:]])chgrp([[:space:]]+-[^[:space:]]+)*[[:space:]]+['\"]?[\$\`]"

  # Whole-line shell comments are stripped before matching: a commented-out
  # `# chgrp -R ps-data ...` is inert, and refusing a deploy over documentation
  # is the kind of false positive that gets a guard disabled. The grep -v runs
  # on grep -n output, so the reported line numbers stay the file's own.
  local nocomment='^[0-9]+:[[:space:]]*#'

  local hits
  if hits="$(grep -nE "$ps_data_re" "$f" | grep -vE "$nocomment")"; then
    local deployed=""
    case "$rel" in
      tools/*) deployed="$TOOLS_DST/${rel#tools/}" ;;
    esac
    echo "  ERROR: DEPLOY REFUSED — cron script would regress the corpus group." >&2
    echo "         skill:  $name" >&2
    echo "         file:   $f" >&2
    echo "         (repo-relative: $rel)" >&2
    echo "         It chgrps to ps-data (gid 2279, 61 members) at:" >&2
    printf '%s\n' "$hits" | sed 's/^/           /' >&2
    if [ -n "$deployed" ] && [ -f "$deployed" ]; then
      echo "         The LIVE deployed copy at" >&2
      echo "           $deployed" >&2
      echo "         reads:" >&2
      grep -nE "(^|[;&|(]|[[:space:]])chgrp" "$deployed" | sed 's/^/           /' >&2 || true
    else
      echo "         The LIVE deployed copy reads ps-users (gid 10000, 3748 members)." >&2
    fi
    echo "         ps-users and ps-data are NOT nested: 3689 ps-users members are" >&2
    echo "         not in ps-data. Deploying this and letting cron run would drop" >&2
    echo "         those corpora from 3748 readers to 61. sdf-docs is hourly." >&2
    echo "         REMEDY: push and merge branch 'fix/cron-chgrp-ps-users' in the" >&2
    echo "         upstream repo for '$name' (staged at" >&2
    echo "         /sdf/data/lcls/ds/prj/prjdat21/results/cwang31/iter6-cron-fix/)," >&2
    echo "         then re-run this deploy. Do NOT cherry-pick the exec-bit fix" >&2
    echo "         alone: it is stacked ON TOP of the chgrp fix on purpose, and" >&2
    echo "         taking it by itself resurrects a dead cron that writes ps-data." >&2
    echo "         There is no override flag, by design." >&2
    echo "         Nothing was written for '$name'." >&2
    return 1
  fi

  if hits="$(grep -nE "$var_re" "$f" | grep -vE "$nocomment")"; then
    if grep -vE '^[[:space:]]*#' "$f" | grep -q 'ps-data'; then
      echo "  ERROR: DEPLOY REFUSED — cron script chgrps to a group this guard cannot" >&2
      echo "         resolve, and the string 'ps-data' appears in the same file." >&2
      echo "         skill:  $name" >&2
      echo "         file:   $f" >&2
      printf '%s\n' "$hits" | sed 's/^/           /' >&2
      echo "         The guard cannot prove the group is not ps-data, and fail-closed" >&2
      echo "         is the rule. Make the group operand a literal, or remove the" >&2
      echo "         ps-data reference. Nothing was written for '$name'." >&2
      return 1
    fi
    echo "  WARN: $rel chgrps to a non-literal group; the ps-data guard could not" >&2
    echo "        statically resolve it. 'ps-data' does not appear anywhere in the" >&2
    echo "        file, so the deploy proceeds — but review it:" >&2
    printf '%s\n' "$hits" | sed 's/^/          /' >&2
  fi

  return 0
}

# ─── Per-skill deploy ─────────────────────────────────────────────────────
deploy_skill() {
  local name="$1"
  local repo="$2"
  local ref="$3"
  local has_harness="$4"
  local cron_script="${5:-}"
  local stage="$STAGING_ROOT/$name"

  echo "── $name ($repo @ $ref)"

  # Clone or update. $ref may be a branch, a tag or a full 40-hex commit SHA.
  # The branch/tag arms below are byte-for-byte what this script always did;
  # SHA refs get their own arms because neither `clone -b <sha>` nor
  # `origin/<sha>` exists.
  #
  # Before either arm: a stage is keyed on the skill NAME, not on the repo, and
  # the reuse arm below fetches from the stage's OWN origin. So when an entry's
  # `repo` changes, the cached clone of the OLD repo is silently reused and
  # reset to the old repo's ref.
  #
  # Verified 2026-08-28: after elog-copilot moved from carbonscott/deploy-opencode
  # to carbonscott/skill-elog-copilot, a stale stage was refreshed to
  # deploy-opencode main and the run died with "harness.source
  # 'claude/skills/elog-copilot' is not a directory in this repo". That failure
  # was loud only because the path happened to be absent in the wrong repo. A
  # wrong repo whose layout still matched would have deployed the WRONG CONTENT
  # with every check passing, which is the case this guard actually exists for.
  #
  # So discard a stage whose origin is not the repo this entry names and let the
  # clone arm rebuild it. `git remote get-url` needs git >= 2.7 (host: 2.43.7).
  if [ -d "$stage/.git" ]; then
    local stage_origin
    stage_origin="$(git -C "$stage" remote get-url origin 2>/dev/null || true)"
    if [ "$stage_origin" != "git@github.com:$repo.git" ]; then
      echo "  stage came from ${stage_origin:-an unknown origin}, not git@github.com:$repo.git — discarding it"
      rm -rf "$stage"
    fi
  fi

  if [ -d "$stage/.git" ]; then
    if is_sha_ref "$ref"; then
      # `git fetch --depth=1 origin <sha>` is served by GitHub
      # (uploadpack.allowAnySHA1InWant); verified on this host against a
      # non-tip commit, so it is not a tip-only special case. FETCH_HEAD is
      # the fetched object. There is no origin/<sha> ref to reset --hard to —
      # the forced detached checkout IS the reset, and it also recovers a
      # stage left dirty or on a branch by an earlier run.
      git -C "$stage" fetch --depth=1 origin "$ref"
      git -C "$stage" checkout -q --force --detach FETCH_HEAD
    else
      git -C "$stage" fetch --depth=1 origin "$ref"
      git -C "$stage" checkout "$ref"
      # Only reset when origin/$ref resolves (branches do; tags/SHAs under
      # --depth=1 do not). Silent || true would swallow real fetch failures.
      if git -C "$stage" rev-parse --verify "origin/$ref" >/dev/null 2>&1; then
        git -C "$stage" reset --hard "origin/$ref"
      fi
    fi
  else
    rm -rf "$stage"
    if is_sha_ref "$ref"; then
      # `git clone --depth=1 -b <sha>` fails with "Remote branch <sha> not
      # found in upstream origin" — -b takes a ref name, and a SHA is not one.
      # init + remote add + shallow fetch of the SHA is the equivalent, and
      # keeps the single-commit shallow shape.
      mkdir -p "$stage"
      git -C "$stage" init -q
      git -C "$stage" remote add origin "git@github.com:$repo.git"
      git -C "$stage" fetch --depth=1 origin "$ref"
      git -C "$stage" checkout -q --detach FETCH_HEAD
    else
      git clone --depth=1 -b "$ref" "git@github.com:$repo.git" "$stage"
    fi
  fi

  # ─── Cron ps-data guard ─────────────────────────────────────────────────
  # Placed HERE deliberately: after the clone (there is nothing to inspect
  # before it) and before source selection, before write_harness_meta(),
  # before render.sh, and before every rsync_and_chmod call — the skill rsync,
  # the claude-tree rsync, the agents/ symlink and the tools/ rsync all come
  # later in this function. A refused skill therefore writes NOTHING anywhere
  # under $DEPLOY_ROOT, which is the requirement: the hazard is precisely the
  # tools/ rsync overwriting the live cron script.
  if [ -n "$cron_script" ]; then
    if ! assert_cron_group_safe "$name" "$stage" "$cron_script"; then
      DEPLOY_FAILED=1
      return 0
    fi
  fi

  # ─── Source selection: manifest harness block vs legacy checked-in tree ──
  # An entry with a 'harness' block is single-source: render from
  # <stage>/<harness.source>, deploy the renders to both harness trees. An entry
  # without one is pre-migration and takes the original path: opencode only,
  # from the repo's checked-in opencode/skills/<name>/, nothing to the claude
  # tree. The two coexist so the manifest can move one entry at a time, and so
  # the campaign has a rollback (docs/design-manifest-harness.md §C2.1).
  local src=""
  local claude_src=""
  local claude_cmd=""
  local kind="skill"
  local srcdir=""
  local meta=""

  if [ "$has_harness" = "1" ]; then
    meta="$META_DIR/$name.json"
    # Malformed harness block -> hard error. NO legacy fallback: that would
    # paper over a typo'd key with a silently different deploy.
    if ! write_harness_meta "$name" "$meta"; then
      DEPLOY_FAILED=1
      return 0
    fi
    if ! srcdir="$(resolve_harness_source "$stage" "$meta")"; then
      echo "         (manifest entry '$name', repo $repo)" >&2
      DEPLOY_FAILED=1
      return 0
    fi
  fi

  if [ -n "$srcdir" ]; then
    local slug rtarget
    # No `//` defaults here: write_harness_meta() already normalised every
    # mandatory key, so exactly one place owns the defaulting.
    kind="$(jq -r '.kind' "$meta")"
    slug="$(jq -r '.slug' "$meta")"
    if [ ! -x "$RENDER" ]; then
      echo "  WARN: $RENDER missing or not executable; cannot render $name" >&2
      return 0
    fi
    echo "  source dir: ${srcdir#$stage/} (from manifest harness.source)"
    # Both harness trees come out of ONE render invocation, so they cannot
    # disagree about the body — that is the whole point of the design.
    if [ "$DEPLOY_CLAUDE" = "1" ]; then rtarget="both"; else rtarget="opencode"; fi
    # DRY_RUN=0 on purpose. DRY_RUN protects $DEPLOY_ROOT, not the staging dir,
    # which this script already clones into unconditionally. Rendering for real
    # is what lets the dry run below show the actual rsync it would perform.
    rm -rf "$stage/.rendered"
    DRY_RUN=0 "$RENDER" --meta "$meta" --target "$rtarget" \
      "$srcdir" "$stage/.rendered" | sed 's/^/  /'
    echo "  ✓ rendered from manifest harness block (kind=$kind, slug=$slug, target=$rtarget)"
    [ "$slug" = "$name" ] || \
      echo "  NOTE: harness slug '$slug' differs from manifest name '$name'"
    if [ "$kind" = "command" ]; then
      # Claude Code reads commands from <config>/commands/<name>.md, so a
      # rendered command has a real destination on that side as of iteration 4.
      # The opencode side still does not: $DEPLOY_ROOT/opencode/commands/ is
      # live hand-maintained state and adopting it is a separate decision (design
      # doc §6). So a kind=command entry deploys to the claude tree only.
      [ "$DEPLOY_CLAUDE" = "1" ] && claude_cmd="$stage/.rendered/claude/commands/$slug.md"
      echo "  NOTE: kind=command — claude/commands only; opencode/commands is not"
      echo "        a deploy destination (design doc §6)"
    else
      src="$stage/.rendered/opencode/skills/$slug/"
      [ "$DEPLOY_CLAUDE" = "1" ] && claude_src="$stage/.rendered/claude/skills/$slug/"
    fi
  elif [ -d "$stage/opencode/skills/$name" ]; then
    echo "  DEPRECATED: no 'harness' block in the manifest entry for '$name'; using" >&2
    echo "              the repo's checked-in opencode/skills/$name/ and writing" >&2
    echo "              nothing to the claude tree. Add a harness block — see" >&2
    echo "              docs/design-manifest-harness.md §A." >&2
    src="$stage/opencode/skills/$name/"
  else
    # Neither shape. Before iteration 4 this fell into the legacy branch and
    # produced one WARN and a zero exit — a deploy that silently shipped nothing.
    echo "  ERROR: $repo matches neither shape:" >&2
    echo "         no 'harness' block in the manifest entry for '$name', and no" >&2
    echo "         opencode/skills/$name/ directory in the repo. Nothing deployed." >&2
    echo "         Fix: add a harness block to $MANIFEST (see" >&2
    echo "         docs/design-manifest-harness.md §A), or check the repo layout." >&2
    DEPLOY_FAILED=1
    return 0
  fi

  # opencode/skills/<name>/
  if [ -z "$src" ]; then
    :  # kind=command — nothing to copy on the opencode side; noted above
  elif [ ! -d "$src" ]; then
    echo "  WARN: $src not present in $repo; skipping skill content"
  else
    rsync_and_chmod "$src" "$SKILLS_DST/$name/"
    echo "  ✓ skill content"
  fi

  # claude/skills/<name>/ — migrated repos only. Same rsync_and_chmod, so the
  # chgrp/chmod g+rX step applies to this tree exactly as it does to opencode.
  if [ -n "$claude_src" ]; then
    if [ ! -d "$claude_src" ]; then
      echo "  WARN: $claude_src not present; skipping claude skill content"
    else
      ensure_claude_root "$CLAUDE_SKILLS_DST"
      rsync_and_chmod "$claude_src" "$CLAUDE_SKILLS_DST/$name/"
      echo "  ✓ claude skill content"
    fi
  fi

  # claude/commands/<name>.md — migrated kind=command repos only.
  if [ -n "$claude_cmd" ]; then
    if [ ! -f "$claude_cmd" ]; then
      echo "  WARN: $claude_cmd not present; skipping claude command"
    else
      ensure_claude_root "$CLAUDE_CMDS_DST"
      rsync_file_and_chmod "$claude_cmd" "$CLAUDE_CMDS_DST/$name.md"
      echo "  ✓ claude command"
    fi
  fi

  # agents/<name> → ../skills/<name>
  # A kind=command repo gets no agent link — a command is not @-invocable.
  local agent_link="$AGENTS_DST/$name"
  if [ "$kind" = "command" ]; then
    echo "  (skipped agents/ symlink: kind=command)"
  elif [ "$DRY_RUN" != "1" ]; then
    # AGENTS_DST is never created anywhere else, and on a virgin deploy root the
    # ln -s below fails with ENOENT, which under `set -euo pipefail` aborts the
    # entire run mid-skill. Inside this branch so a dry run still writes NOTHING
    # (the rule rsync_and_chmod lines 86-90 enforce), and after the kind=command
    # arm above so a command-only deploy never creates an agents/ dir it will
    # never use.
    mkdir -p "$AGENTS_DST"
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

  while IFS=$'\t' read -r name repo ref has_cron has_harness cron_script; do
    if [ ${#wanted[@]} -gt 0 ]; then
      local match=0
      for w in "${wanted[@]}"; do
        [ "$w" = "$name" ] && match=1 && break
      done
      [ "$match" = "0" ] && continue
    fi
    matched+=("$name")
    deploy_skill "$name" "$repo" "$ref" "$has_harness" "$cron_script"
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

  if [ "$DEPLOY_FAILED" != "0" ]; then
    echo "ERROR: one or more skills failed to deploy (unknown layout, malformed" >&2
    echo "       harness block, or the cron ps-data guard); see above." >&2
    exit 3
  fi
}

main "$@"
