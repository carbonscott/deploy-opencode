"""Refuse to publish a proof folder that leaks personal details or secrets.

    python3 -I tools/proofs/scan.py docs/proofs/<slug> [--allow REGEX ...]

The gh-pages site is public, so this runs before every publish. It reads every
text file in the folder, and also DECODES the gzip+base64 screencast that
proof-report pages embed (<script id="cast-gz">), because a terminal recording
is where a name or an email address slips in unnoticed. Example: a fresh
install-claude-lcls.sh run prints the GnuPG key it makes,
"<Real Name> (keyswitch) <user@slac.stanford.edu>".

Exit 0 = clean, 1 = findings (each printed as file: kind: masked sample).
"""
import base64, gzip, os, re, sys

PATTERNS = {
    "email": re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    "api key": re.compile(r"\bsk-[A-Za-z0-9_-]{16,}"),
    "private key": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    "gnupg user id": re.compile(r"making a GnuPG key for it: (?!\*+ )[^\n\\]{3,}\(keyswitch\)"),
}
ALLOW = [r"noreply@anthropic\.com", r"@example\.(com|org)", r"@users\.noreply\.github\.com"]


def texts(path):
    with open(path, errors="replace") as f:
        s = f.read()
    yield path, s
    m = re.search(r'<script[^>]*id="cast-gz"[^>]*>([^<]+)</script>', s)
    if m:
        cast = gzip.decompress(base64.b64decode(m.group(1).strip())).decode("utf-8", "replace")
        yield path + " (embedded screencast)", cast


def mask(x):
    return x[:2] + "*" * max(len(x) - 4, 1) + x[-2:]


def main():
    args = sys.argv[1:]
    allow = list(ALLOW)
    while "--allow" in args:
        i = args.index("--allow"); allow.append(args[i + 1]); del args[i:i + 2]
    if len(args) != 1 or not os.path.isdir(args[0]):
        sys.exit(__doc__)
    hits = 0
    for root, _, files in os.walk(args[0]):
        for name in sorted(files):
            if not name.endswith((".html", ".md", ".json", ".tsv", ".txt", ".sh", ".py", ".log")):
                continue
            for where, text in texts(os.path.join(root, name)):
                for kind, rx in PATTERNS.items():
                    for m in rx.finditer(text):
                        if any(re.search(a, m.group(0)) for a in allow):
                            continue
                        hits += 1
                        print("%s: %s: %s" % (where, kind, mask(m.group(0))))
    print("scan: %s" % ("clean" if not hits else "%d finding(s)" % hits), file=sys.stderr)
    sys.exit(1 if hits else 0)


main()
