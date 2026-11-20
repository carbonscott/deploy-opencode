# Proof: claude-lcls launcher (2026-11-20)

End-to-end evidence for the shared launcher and installer changes on this branch.
Everything ran on sdfiana024, in a shell set up the way a client reported it:
`export ANTHROPIC_AUTH_TOKEN=yourKeyHere`.

| File | What it is |
|---|---|
| `proof.html` | The proof page: verdicts, a one-take screencast (09:52–10:02 PT) with chapters, the checks table, captured screens, an independent read-back from `/proc`, findings and an audit trail. Self-contained; download it and open it in a browser. |
| `proof.sh` | The check script. Each expected value is written in it before its measurement. Runs every case in a throwaway `HOME` under node-local `/tmp` with its own `GNUPGHOME`. |
| `recheck.sh` | The re-check chapter run in the recorded take, after three first-pass checks failed for reasons in the test script (see below). |
| `checks-take.tsv` | Results of the recorded take: 24 PASS, 3 FAIL (A4, E1, H1), plus re-checks A4r, E1r, H1r, all PASS. |
| `checks-rerun.tsv` | Results of the corrected `proof.sh`, run end to end afterwards (10:03–10:07 PT, unrecorded): 24 of 24 PASS. |

The three first-pass failures were test-design errors, not faults in the change:

- **A4** mixed two bugs: the client home exports the token, so the old function was stuck in the 401 retry loop before the repo pin could show.
- **E1** was a grading typo: `dir ok=True` against the printed `DIR ok=True`.
- **H1** could not time out: the gateway answers the installer's identical test prompt from a cache in under 1 s.

`proof.sh` now isolates A4, greps the exact strings for E1, and tests H1 against a local listener that never completes TLS, so no request or key is sent to it.

To run it again (on S3DF, as a ps-users member):

```bash
P=/sdf/scratch/users/$USER/lcls-proof && mkdir -p -m 700 $P
git clone --branch fix/claude-lcls-launcher https://github.com/carbonscott/deploy-opencode $P/repo
sed -i "s|^P=.*|P=$P|" $P/repo/docs/proofs/2026-11-20-claude-lcls-launcher/proof.sh
export ANTHROPIC_AUTH_TOKEN=yourKeyHere
bash $P/repo/docs/proofs/2026-11-20-claude-lcls-launcher/proof.sh    # results in $P/results/checks.tsv
```

Each throwaway home holds a copy of the shared key while the script runs. Delete `/tmp/lcls-proof.*` and stop their GnuPG agents afterwards (`GNUPGHOME=<home>/gnupg gpgconf --kill gpg-agent`).
