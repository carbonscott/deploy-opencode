#!/usr/bin/env bash
# publish-proof.sh -- put proof folders on the public GitHub Pages site.
#
#   tools/proofs/publish-proof.sh docs/proofs/<slug> [docs/proofs/<slug> ...]
#
# Each folder needs proof.html and meta.json (see docs/proofs/README.md). The
# folder is copied to the gh-pages branch as <slug>/, the gallery index.html is
# rebuilt from every <slug>/meta.json there, and the branch is pushed. Pages
# serves it at https://<owner>.github.io/<repo>/<slug>/proof.html within a
# minute or so, so a PR can link the proof while it is still under review.
#
# The site is PUBLIC. tools/proofs/scan.py runs first and refuses a folder that
# holds an email address, an API key or a GnuPG user id -- including inside the
# embedded screencast. Mask those at the source and re-run.
#
# Publishing a slug again replaces it. Nothing is ever deleted from the site by
# this script; to retire a proof, remove its folder on gh-pages by hand.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$here" rev-parse --show-toplevel)"
[ "$#" -ge 1 ] || { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

for d in "$@"; do
  [ -f "$d/proof.html" ] && [ -f "$d/meta.json" ] || { echo "publish-proof: $d needs proof.html and meta.json" >&2; exit 2; }
  python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m.get("title") and m.get("date"), "meta.json needs title and date"' "$d/meta.json"
  python3 -I "$here/scan.py" "$d" || { echo "publish-proof: $d failed the privacy scan; nothing was published" >&2; exit 1; }
done

remote="$(git -C "$repo_root" remote get-url origin)"
slug_path="${remote#*github.com[:/]}"; slug_path="${slug_path%.git}"     # owner/repo
repo_url="https://github.com/$slug_path"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

if git ls-remote --exit-code --heads "$remote" gh-pages >/dev/null 2>&1; then
  git clone -q --depth 1 --branch gh-pages --single-branch "$remote" "$work/site"
else
  git init -q -b gh-pages "$work/site"; git -C "$work/site" remote add origin "$remote"
fi
touch "$work/site/.nojekyll"                  # serve files as they are, no Jekyll

for d in "$@"; do
  slug="$(basename "$(cd "$d" && pwd)")"
  rm -rf "${work:?}/site/$slug"; mkdir -p "$work/site/$slug"
  cp -p "$d"/* "$work/site/$slug/"
  printf '<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=proof.html"><title>%s</title><a href="proof.html">proof.html</a>\n' "$slug" > "$work/site/$slug/index.html"
  echo "publish-proof: staged $slug"
done
python3 -I "$here/build-index.py" "$work/site" "$repo_url"

git -C "$work/site" add -A
if git -C "$work/site" diff --cached --quiet; then
  echo "publish-proof: gh-pages already has these files; nothing to push"
else
  git -C "$work/site" commit -q -m "proofs: publish $(for d in "$@"; do basename "$d"; done | tr '\n' ' ')"
  git -C "$work/site" push -q origin HEAD:gh-pages
fi
owner="${slug_path%%/*}"; name="${slug_path#*/}"
for d in "$@"; do echo "https://$owner.github.io/$name/$(basename "$(cd "$d" && pwd)")/proof.html"; done
