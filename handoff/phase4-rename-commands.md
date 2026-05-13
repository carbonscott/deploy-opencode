# Phase 4: GitHub rename commands

Two existing remotes that don't follow the `skill-*` prefix convention need renaming. **Run these manually** (per policy: maintainer runs all GitHub mutations).

## Renames

```bash
gh repo rename --repo carbonscott/ask-slac-ai-tools skill-ask-slac-ai-tools
gh repo rename --repo carbonscott/xpm-seq-skills skill-xpm-seq
```

## What this affects

After rename:
- Anyone with a local clone using the old URL will see `git fetch`/`git pull` fail until they update the remote (`git remote set-url origin git@github.com:carbonscott/skill-<new-name>.git`).
- The deployed copies at `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/ask-slac-ai-tools/` and `/sdf/group/lcls/ds/dm/apps/dev/opencode/skills/xpm-seq/` are unaffected (they're populated by `deploy.sh` which pulls from the new name listed in `skills.manifest.json`).
- GitHub automatically forwards old URLs for `git clone` and HTTP, but it's still good hygiene to update any hardcoded references.

## After rename, verify

```bash
gh repo view carbonscott/skill-ask-slac-ai-tools --json name
gh repo view carbonscott/skill-xpm-seq --json name
```

Both should show the new name. The manifest already references the new names — no edits needed there.

## Related: Phase 3 (cuda-docs) repo creation

This is a **create**, not a rename. cuda-docs has no existing remote.

```bash
gh repo create carbonscott/skill-cuda-docs \
  --public \
  --description "CUDA documentation search wrapper for Claude/opencode agents. Operates on central markdown docs at /sdf/group/lcls/ds/dm/apps/dev/data/cuda-docs/."
```

After this exists, the staged content at `/tmp/skill-cuda-docs-stage/` on the worktree host can be pushed:

```bash
cd /tmp/skill-cuda-docs-stage
git remote add origin git@github.com:carbonscott/skill-cuda-docs.git
git push -u origin main
```
