"""Mask personal details in a proof page, including its embedded screencast.

    python3 -I tools/proofs/mask.py docs/proofs/<slug>/proof.html [--literal TEXT ...]

Finds the values to hide with the same rules as scan.py (email addresses and the
name in a "making a GnuPG key for it: <Name> (keyswitch) <email>" line) plus any
--literal, then replaces EVERY occurrence with the same number of '*' in the
page text and in the gzip+base64 asciicast inside <script id="cast-gz">.
Same length keeps the terminal layout intact. The cast is masked as one
continuous stream and split back at the original event boundaries, so a value
that the terminal happened to print across two output chunks is masked too.

Prints only how many occurrences were masked, never the values. Edits in place.
"""
import base64, gzip, json, re, sys

ALLOW = re.compile(r"noreply@anthropic\.com|@example\.(com|org)|@users\.noreply\.github\.com")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
GPG_NAME = re.compile(r"making a GnuPG key for it: (.+?) \(keyswitch\)")


def find_values(text, literals):
    vals = set(literals)
    vals.update(m.group(0) for m in EMAIL.finditer(text) if not ALLOW.search(m.group(0)))
    vals.update(m.group(1) for m in GPG_NAME.finditer(text) if set(m.group(1)) != {"*"})
    return sorted((v for v in vals if v), key=len, reverse=True)


def mask_text(text, vals):
    n = 0
    for v in vals:
        n += text.count(v)
        text = text.replace(v, "*" * len(v))
    return text, n


def main():
    args = sys.argv[1:]
    lits = []
    while "--literal" in args:
        i = args.index("--literal"); lits.append(args[i + 1]); del args[i:i + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    path = args[0]
    page = open(path).read()
    m = re.search(r'(<script[^>]*id="cast-gz"[^>]*>)([^<]+)(</script>)', page)
    cast_lines, events, stream = [], [], ""
    if m:
        cast_lines = gzip.decompress(base64.b64decode(m.group(2).strip())).decode().splitlines()
        events = [json.loads(l) for l in cast_lines[1:]]
        stream = "".join(e[2] for e in events if e[1] == "o")
    vals = find_values(page + "\n" + stream, lits)
    total = 0
    if m:
        masked, n = mask_text(stream, vals); total += n
        pos = 0
        for e in events:                      # same-length masking: split back at the old boundaries
            if e[1] == "o":
                e[2] = masked[pos:pos + len(e[2])]; pos += len(e[2])
        new_cast = "\n".join([cast_lines[0]] + [json.dumps(e, ensure_ascii=True) for e in events]) + "\n"
        b64 = base64.b64encode(gzip.compress(new_cast.encode(), 9)).decode()
        page = page[:m.start(2)] + b64 + page[m.end(2):]
    head, n = mask_text(page[:m.start(2)] if m else page, vals); total += n
    page = head + (page[m.start(2):] if m else "")
    open(path, "w").write(page)
    print("mask: %d value(s), %d occurrence(s) masked in %s" % (len(vals), total, path))


main()
