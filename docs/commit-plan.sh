#!/usr/bin/env bash
#
# commit-plan.sh — make the six commits described in docs/commit-plan.md.
#
# PRINTS ITS PLAN AND WRITES NOTHING unless given --run. Read
# docs/commit-plan.md first; this script is only the mechanical half of it.
#
# It touches ONLY the paths listed below, all of them produced by the
# single-source / renderer / claude-harness work of 2026-08-26. Pre-existing
# human work (category (b) in the plan) and junk (category (c)) are never
# staged, never committed, never deleted. Verify that yourself: the script
# prints `git status` before and after.
#
# Usage:
#   ./docs/commit-plan.sh                  # dry run: plan + path check
#   ./docs/commit-plan.sh --run            # do it
#   ./docs/commit-plan.sh --run --branch X # on branch X instead of the default
#   ./docs/commit-plan.sh --run --no-branch# commit onto the current branch
#
# It never runs `git push`.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="iteration-5-single-source"
RUN=0
MAKE_BRANCH=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run)       RUN=1 ;;
        --branch)    BRANCH="$2"; shift ;;
        --no-branch) MAKE_BRANCH=0 ;;
        -h|--help)   sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

cd "$REPO"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo: $REPO" >&2; exit 2; }

# ── The six commits ───────────────────────────────────────────────────────
# One entry per commit: subject, body, then the paths. Paths are passed to
# `git add -A --` so that deletions are staged as deletions.

C1_SUBJECT="Render skills from one source into both harness trees"
C1_BODY="A skill body had to be maintained twice, under opencode/skills/ and
under claude/skills/, and the two drifted. render.sh makes src/<name>/ the
single source and both harness trees build outputs; migrate.sh moves an
existing skill into that shape. The equivalence report is the evidence that
rendering reproduces what was there before."
C1_PATHS=(render.sh migrate.sh docs/design-single-source-skills.md docs/render-equivalence-report.md)

C2_SUBJECT="Move the eight alignment skills to src/ as their single source"
C2_BODY="The first eight skills through migrate.sh, so the design is proven on
real content rather than fixtures. The claude/skills/*/SKILL.md deletions are
the other half of the move: committing the additions alone would leave two
copies of every body, which is the duplication this removes. The two
opencode/commands/ changes are the renderer quoting argument-hint consistently
— output, not hand edits.

claude/commands/ and the rendered opencode/commands/ are build outputs and
belong in .gitignore once rendering is wired into deploy. They are committed
now because opencode/commands/ is live hand-maintained state that deploy.sh
deliberately does not own (design doc section 6)."
C2_PATHS=(src claude/skills/align claude/skills/approval claude/skills/breakdown
          claude/skills/clarify claude/skills/handoff claude/skills/latent-demand
          claude/skills/no-eager claude/skills/no-op
          claude/commands
          opencode/commands/handoff.md opencode/commands/latent-demand.md)

C3_SUBJECT="Deploy a Claude Code tree alongside the opencode tree"
C3_BODY="The team is moving to Claude Code and the central deployment only
populated an opencode tree. deploy.sh now writes \$DEPLOY_ROOT/claude/ for
migrated repos, creating it with the right group rather than whatever mkdir
gives, and errors loudly on a repo matching neither layout instead of silently
shipping nothing. The install script and settings template are how a user
points at that tree."
C3_PATHS=(deploy.sh claude/install-claude-lcls.sh claude/settings.template.json
          docs/claude-code-lcls-setup.md docs/deploy-permissions.md)

C4_SUBJECT="Check deployed skills against their source for drift"
C4_BODY="The deployed cuda-docs skill was three months stale: repo commit
7da2b2d (2026-05-17) bundled its docs and made paths skill-relative, deploy.sh
was never re-run, and nothing noticed. This renders each skill from its repo
and diffs against what is deployed. Deliberately read-only — a drift detector
that self-heals hides the fact that someone is editing deployed files."
C4_PATHS=(tools/skill-drift docs/skill-drift-check.md)

C5_SUBJECT="Add a backup and rollback path for the live deploy"
C5_BODY="deploy.sh rsyncs with --delete and has never been run against the live
tree, so a bad first run could remove files with no way back. This captures the
160 entries / 513 KB deploy.sh can actually reach — modes, setgid bits, group
ownership, symlinks and POSIX ACLs included — into a 157 KB archive stored off
the deploy tree, and restores it in half a second. Restore refuses by default
and needs two separate gates to touch production."
C5_PATHS=(tools/deploy-backup docs/deploy-rollback.md)

C6_SUBJECT="Record what iterations 2-5 measured"
C6_BODY="The reports carry the measurements the design rests on: what was
tested against fixtures rather than reality, the askcode pilot, and the
production drift found along the way. Committed last so the code commits read
on their own."
C6_PATHS=(docs/iteration-2-report.md docs/iteration-3-pilot-report.md
          docs/iteration-4-report.md docs/iteration-5-rehearsal.md
          docs/askcode-merge-2026-08-26.md docs/commit-plan.md docs/commit-plan.sh)

COMMITS=(C1 C2 C3 C4 C5 C6)

# ── Plan ──────────────────────────────────────────────────────────────────
echo "repo:      $REPO"
echo "HEAD:      $(git rev-parse --short HEAD) $(git log -1 --format=%s)"
echo "branch:    $(git rev-parse --abbrev-ref HEAD)"
if [[ "$MAKE_BRANCH" == "1" ]]; then
    echo "will use:  $BRANCH (created from HEAD if absent)"
else
    echo "will use:  current branch (--no-branch)"
fi
echo

# A commit whose subject is already in the log has been applied; its paths are
# expected to be gone from `git status` and, for the moved bodies, gone from the
# working tree entirely. Re-running the script must say so rather than claim the
# tree is broken.
# NOTE: not `git log --format=%s | grep -q`. grep -q exits on the first match,
# git log takes SIGPIPE, and under `set -o pipefail` the whole pipeline returns
# 141 — so the check silently reports "not applied" every time.
already_applied() {
    [[ -n "$(git log --format=%s --fixed-strings --grep="$1" -1)" ]]
}

missing=0
for c in "${COMMITS[@]}"; do
    subject_var="${c}_SUBJECT"; paths_var="${c}_PATHS[@]"
    if already_applied "${!subject_var}"; then
        echo "── ${!subject_var}"
        echo "   ALREADY COMMITTED ($(git log --format='%h' --fixed-strings --grep="${!subject_var}" -1)) — nothing to do"
        echo
        continue
    fi
    echo "── ${!subject_var}"
    for p in "${!paths_var}"; do
        if [[ -e "$p" ]]; then
            n=$(git status --porcelain -uall -- "$p" | wc -l)
            printf '   %-52s %s changed entr%s\n' "$p" "$n" "$([[ $n == 1 ]] && echo y || echo ies)"
        elif git ls-files --error-unmatch "$p" >/dev/null 2>&1 \
             || [[ -n "$(git status --porcelain -uall -- "$p")" ]]; then
            printf '   %-52s (deleted — staged as a deletion)\n' "$p"
        else
            printf '   %-52s MISSING\n' "$p"
            missing=1
        fi
    done
    echo
done

if [[ "$missing" == "1" ]]; then
    echo "ERROR: one or more paths are missing. The tree is not in the state this" >&2
    echo "       plan was written against. Re-read docs/commit-plan.md." >&2
    exit 2
fi

echo "NOT touched by this script (pre-existing human work and junk):"
git status --porcelain -uall > /tmp/commit-plan-before.$$
touched=$(for c in "${COMMITS[@]}"; do paths_var="${c}_PATHS[@]"; printf '%s\n' "${!paths_var}"; done)
git status --porcelain -uall | sed 's/^...//' | while read -r p; do
    keep=1
    while read -r t; do [[ "$p" == "$t"* ]] && keep=0 && break; done <<< "$touched"
    [[ "$keep" == "1" ]] && echo "   $p"
done | head -100
echo "   ($(git status --porcelain -uall | wc -l) entries in git status in total)"
echo

if [[ "$RUN" != "1" ]]; then
    echo "DRY RUN. Nothing was written. Re-run with --run to make these commits."
    exit 0
fi

# ── Act ───────────────────────────────────────────────────────────────────
if [[ -n "$(git diff --cached --name-only)" ]]; then
    echo "ERROR: the index is not empty. Sort that out first — this script will not" >&2
    echo "       commit staged changes it did not stage itself." >&2
    exit 2
fi

if [[ "$MAKE_BRANCH" == "1" ]]; then
    if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        echo "branch $BRANCH already exists; checking it out"
        git checkout "$BRANCH"
    else
        git checkout -b "$BRANCH"
    fi
fi

for c in "${COMMITS[@]}"; do
    subject_var="${c}_SUBJECT"; body_var="${c}_BODY"; paths_var="${c}_PATHS[@]"
    if already_applied "${!subject_var}"; then
        echo "── skipping '${!subject_var}': already committed"
        continue
    fi
    git add -A -- "${!paths_var}"
    if [[ -z "$(git diff --cached --name-only)" ]]; then
        echo "── skipping '${!subject_var}': nothing to commit"
        continue
    fi
    echo "── committing '${!subject_var}' ($(git diff --cached --name-only | wc -l) files)"
    git commit -q -m "${!subject_var}" -m "${!body_var}"
    git log -1 --format='   %h %s'
done

echo
echo "── result"
git log --oneline -$(( ${#COMMITS[@]} + 2 ))
echo
echo "── what is still uncommitted (should be only categories (b) and (c))"
git status --porcelain -uall
echo
echo "Nothing was pushed. Review, then push yourself."
