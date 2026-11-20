# Proofs

A proof is end-to-end evidence that a change works, attached to the pull request
that makes it. Each one gets a page on the project's public GitHub Pages site,
and a gallery lists them all, newest first:

**https://carbonscott.github.io/deploy-opencode/**

## Layout

One folder per proof, named `<date>-<slug>`:

```
docs/proofs/2026-11-20-claude-lcls-launcher/
├── proof.html     the page: self-contained, opens offline
├── meta.json      title, date, PR, host, result, summary (feeds the gallery)
├── proof.sh       the checks, with expected values written before the run
└── ...            raw results (*.tsv), helper scripts, a README if useful
```

`meta.json`:

```json
{"title": "claude-lcls launcher", "date": "2026-11-20", "pr": 57,
 "host": "sdfiana024", "result": "24/24 PASS",
 "summary": "One or two sentences on what was proved."}
```

## Publishing

```bash
tools/proofs/publish-proof.sh docs/proofs/<date>-<slug>
```

This copies the folder to the `gh-pages` branch, rebuilds the gallery and
pushes. The page is live at
`https://carbonscott.github.io/deploy-opencode/<date>-<slug>/proof.html`
within a minute or two, before the PR merges, so put that link in the PR.

**The site is public.** `tools/proofs/scan.py` runs first and refuses a folder
holding an email address, an API key or a GnuPG user id, including inside the
embedded screencast. Mask at the source (same-length `*`, so the recording's
layout holds) and run it again. Things that have leaked this way: the shared
key's last four characters, which `keyswitch` prints, and
`<Real Name> (keyswitch) <user@slac.stanford.edu>`, which a fresh installer run
prints when it makes a GnuPG key.

Publishing a slug again replaces it. The script never deletes anything from the
site.
