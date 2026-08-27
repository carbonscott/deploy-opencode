#!/usr/bin/env bash
# Validate skills.manifest.json for the manifest-carried harness metadata.
#
# Every element of .skills[] should carry a "harness" object holding the
# metadata that used to live in an in-repo skill.json (see
# docs/design-manifest-harness.md section A). This script is the gate: it
# checks that every entry has a well-formed harness block, and reports ALL
# problems rather than stopping at the first, because an operator fixing a
# manifest wants the whole list.
#
# Usage:
#   ./validate-manifest.sh [<manifest>]        # default: <script dir>/skills.manifest.json
#   ./validate-manifest.sh --counts [<manifest>]
#   ./validate-manifest.sh --help
#
# Exit codes:
#   0  every entry carries a well-formed harness block
#   1  usage error, missing/unreadable manifest, or manifest is not valid JSON
#   2  one or more validation failures
#
# Requires jq (tested on 1.6 — no jq 1.7 builtins) and bash 4.4.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNTS_ONLY=0
MANIFEST=""

usage() {
    sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --counts)
            COUNTS_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [ -n "$MANIFEST" ]; then
                echo "ERROR: at most one manifest path may be given" >&2
                exit 1
            fi
            MANIFEST="$1"
            shift
            ;;
    esac
done

[ -n "$MANIFEST" ] || MANIFEST="$SCRIPT_DIR/skills.manifest.json"

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but was not found on PATH" >&2
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest not found: $MANIFEST" >&2
    exit 1
fi
if [ ! -r "$MANIFEST" ]; then
    echo "ERROR: manifest not readable: $MANIFEST" >&2
    exit 1
fi
if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
    echo "ERROR: manifest is not valid JSON: $MANIFEST" >&2
    exit 1
fi
if ! jq -e '(.skills | type) == "array"' "$MANIFEST" >/dev/null 2>&1; then
    echo "ERROR: .skills is missing or not an array: $MANIFEST" >&2
    exit 1
fi

# --- the two proof counts (jq 1.6 compatible, exact complements) -------------
TOTAL=""
WITH=""
WITHOUT=""
TOTAL="$(jq '.skills | length' "$MANIFEST")"
WITH="$(jq '[.skills[] | select((.harness | type) == "object")] | length' "$MANIFEST")"
WITHOUT="$(jq '[.skills[] | select((.harness | type) != "object")] | length' "$MANIFEST")"

if [ "$COUNTS_ONLY" -eq 1 ]; then
    echo "$TOTAL entries: $WITH with a harness block, $WITHOUT without."
    exit 0
fi

if [ "$TOTAL" -eq 0 ]; then
    echo "ERROR: .skills is empty: $MANIFEST" >&2
    exit 1
fi

# --- one jq pass over every entry, emitting name<TAB>severity<TAB>message ----
# Severity is one of OK / FAIL / WARN. bash below only formats and counts.
JQ_PROG='
def trim: gsub("^[ \t\r\n]+"; "") | gsub("[ \t\r\n]+$"; "");
def nonempty_string($v): ($v | type) == "string" and (($v | trim) | length) > 0;

# duplicate rendered slugs across entries (render.sh keys the on-disk
# directory / filename on harness.slug, defaulting to harness.name, defaulting
# to the manifest name)
([ .skills[]
   | (if (.harness | type) == "object"
      then (.harness.slug // .harness.name // .name)
      else .name end)
   | tostring ]
 | group_by(.) | map(select(length > 1) | .[0]) ) as $dupslugs
|
([ .skills[] | .name | tostring ]
 | group_by(.) | map(select(length > 1) | .[0]) ) as $dupnames
|
.skills
| to_entries[]
| .key as $i
| .value as $e
| (if ($e.name | type) == "string" and ($e.name | length) > 0
   then $e.name else ("<entry #" + ($i | tostring) + ">") end) as $nm
| $e.harness as $h
| (
    # ---- manifest-level per-entry checks (independent of harness) ----
    ( if nonempty_string($e.name) | not
      then ["FAIL", ".name is missing or not a non-empty string"]
      elif ($e.name | test("/"))
      then ["FAIL", ".name must not contain \"/\" (got \"" + $e.name + "\")"]
      elif ($dupnames | index($e.name)) != null
      then ["FAIL", ".name \"" + $e.name + "\" is duplicated across entries"]
      else empty end ),

    ( if nonempty_string($e.repo) | not
      then ["FAIL", ".repo is missing or not a non-empty string"]
      elif ($e.repo | test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$") | not)
      then ["FAIL", ".repo must look like <owner>/<name> (got \"" + $e.repo + "\")"]
      else empty end ),

    # ---- harness checks ----
    ( if ($h | type) != "object" then
        ["FAIL", "harness block is missing or not an object"]
      else
        (
          ( if ($h | has("kind")) and ($h.kind != "skill") and ($h.kind != "command")
            then ["FAIL", "harness.kind must be \"skill\" or \"command\" (got " + ($h.kind | tojson) + ")"]
            else empty end ),

          ( if nonempty_string($h.description_auto) | not
            then ["FAIL", "harness.description_auto is missing or empty"]
            else empty end ),

          ( if nonempty_string($h.description_menu) | not
            then ["FAIL", "harness.description_menu is missing or empty"]
            else empty end ),

          ( if ($h | has("source")) then
              ( if nonempty_string($h.source) | not
                then ["FAIL", "harness.source is empty or not a string"]
                elif ($h.source | startswith("/"))
                then ["FAIL", "harness.source must be repo-relative, not absolute (got \"" + $h.source + "\")"]
                elif (($h.source | split("/") | index("..")) != null)
                then ["FAIL", "harness.source must not contain a \"..\" segment (got \"" + $h.source + "\")"]
                elif ($h.source | endswith("/"))
                then ["WARN", "harness.source has a trailing \"/\" (will be stripped)"]
                else empty end )
            else empty end ),

          ( if ($h | has("name")) then
              ( if nonempty_string($h.name) | not
                then ["FAIL", "harness.name is empty or not a string"]
                elif ($h.name | test("/"))
                then ["FAIL", "harness.name must not contain \"/\" (got \"" + $h.name + "\")"]
                else empty end )
            else empty end ),

          ( if ($h | has("slug")) then
              ( if nonempty_string($h.slug) | not
                then ["FAIL", "harness.slug is empty or not a string"]
                elif ($h.slug | test("/"))
                then ["FAIL", "harness.slug must not contain \"/\" (got \"" + $h.slug + "\")"]
                else empty end )
            else empty end ),

          ( if ($h | has("argument_hint")) then
              ( if ($h.argument_hint | type) != "string"
                then ["FAIL", "harness.argument_hint must be a string"]
                elif (($h.kind // "skill") == "skill")
                then ["FAIL", "harness.argument_hint is not allowed for kind=skill (only kind=command emits it)"]
                else empty end )
            else empty end ),

          ( if ($h | has("user_invocable")) then
              ( if ($h.user_invocable | type) != "boolean"
                then ["FAIL", "harness.user_invocable must be a boolean"]
                elif (($h.kind // "skill") == "skill") and ($h.user_invocable == true)
                then ["WARN", "kind=skill but user_invocable is set (dead metadata, ignored)"]
                else empty end )
            else empty end ),

          ( if (($h.slug // $h.name // $e.name | tostring) as $s
                | ($dupslugs | index($s)) != null)
            then ["FAIL", "rendered slug \"" + ($h.slug // $h.name // $e.name | tostring) + "\" is duplicated across entries"]
            else empty end ),

          ( if nonempty_string($h.description_menu) and (($h.description_menu | length) > 120)
            then ["WARN", "harness.description_menu is " + ($h.description_menu | length | tostring) + " chars (>120); it is an @-menu label"]
            else empty end )
        )
      end )
  ) as $problem
| [$nm, $problem[0], $problem[1]] | @tsv
'

REPORT=""
if ! REPORT="$(jq -r "$JQ_PROG" "$MANIFEST")"; then
    echo "ERROR: failed to evaluate the manifest with jq" >&2
    exit 1
fi

# Entries with no problem row at all are the clean ones; synthesise an OK line.
OK_ROWS=""
if ! OK_ROWS="$(jq -r '
    .skills[]
    | select((.harness | type) == "object")
    | [ (.name | tostring), "OK",
        ("harness: kind=" + (.harness.kind // "skill")
         + " source=" + (.harness.source // ("claude/skills/" + (.name | tostring)))) ]
    | @tsv' "$MANIFEST")"; then
    echo "ERROR: failed to evaluate the manifest with jq" >&2
    exit 1
fi

echo "── $MANIFEST"

fail_count=0
warn_count=0
declare -A HAS_FAIL=()

if [ -n "$REPORT" ]; then
    while IFS=$'\t' read -r nm sev msg; do
        [ -n "$nm" ] || continue
        case "$sev" in
            FAIL)
                HAS_FAIL["$nm"]=1
                printf '  %s %-28s %s\n' "✗" "$nm" "$msg"
                fail_count=$((fail_count + 1))
                ;;
            WARN)
                printf '  %s %-28s %s\n' "!" "$nm" "WARN: $msg"
                warn_count=$((warn_count + 1))
                ;;
            *)
                printf '  %s %-28s %s\n' "?" "$nm" "$sev $msg"
                ;;
        esac
    done <<< "$REPORT"
fi

if [ -n "$OK_ROWS" ]; then
    while IFS=$'\t' read -r nm sev msg; do
        [ -n "$nm" ] || continue
        if [ -z "${HAS_FAIL[$nm]:-}" ]; then
            printf '  %s %-28s %s\n' "✓" "$nm" "$msg"
        fi
    done <<< "$OK_ROWS"
fi

echo
echo "$TOTAL entries: $WITH with a harness block, $WITHOUT without."

if [ "$fail_count" -gt 0 ]; then
    echo "FAIL: $fail_count validation failure(s), $warn_count warning(s)."
    exit 2
fi

if [ "$warn_count" -gt 0 ]; then
    echo "OK: every entry carries a well-formed harness block ($warn_count warning(s))."
else
    echo "OK: every entry carries a well-formed harness block."
fi
exit 0
