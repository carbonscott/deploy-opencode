"""Write the gallery page (index.html) for a checkout of the gh-pages branch.

    python3 -I tools/proofs/build-index.py <site-dir> <repo-url>

Every <site-dir>/<slug>/meta.json becomes one row, newest first. meta.json:
    {"title": "...", "date": "YYYY-MM-DD", "pr": 57, "host": "sdfiana024",
     "result": "24/24 PASS", "summary": "one or two sentences"}
Each row links to <slug>/proof.html, the PR, and the folder in the repo.
"""
import html, json, os, sys

site, repo = sys.argv[1], sys.argv[2].rstrip("/")
esc = html.escape
rows = []
for slug in sorted(os.listdir(site)):
    p = os.path.join(site, slug, "meta.json")
    if os.path.isfile(p):
        m = json.load(open(p))
        m["slug"] = slug
        rows.append(m)
rows.sort(key=lambda m: (m.get("date", ""), m["slug"]), reverse=True)


def row(m):
    pr = m.get("pr")
    links = ['<a href="%s/proof.html">Open proof</a>' % esc(m["slug"])]
    if pr:
        links.append('<a href="%s/pull/%s">PR #%s</a>' % (esc(repo), esc(str(pr)), esc(str(pr))))
    links.append('<a href="%s/tree/main/docs/proofs/%s">Scripts and results</a>' % (esc(repo), esc(m["slug"])))
    return """
    <article class="proof">
      <div class="meta"><time datetime="{d}">{d}</time><span>{host}</span></div>
      <h2><a href="{slug}/proof.html">{title}</a></h2>
      <p>{summary}</p>
      <p class="result">{result}</p>
      <p class="links">{links}</p>
    </article>""".format(d=esc(m.get("date", "")), host=esc(m.get("host", "")), slug=esc(m["slug"]),
                         title=esc(m.get("title", m["slug"])), summary=esc(m.get("summary", "")),
                         result=esc(m.get("result", "")), links=" · ".join(links))


page = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>deploy-opencode Proofs</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
/* One reading column of proof records, newest first; same type and palette as the proof pages. */
:root {{
  --bg: #F4F6F8; --surface: #FFFFFF; --fg: #141A22; --muted: #566170; --line: #D8DEE6; --accent: #1D5BB8; --pass: #1B7442;
  --sans: "IBM Plex Sans", "Segoe UI", system-ui, sans-serif; --mono: "IBM Plex Mono", ui-monospace, Menlo, Consolas, monospace;
}}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{
  --bg: #0D1116; --surface: #141A21; --fg: #E3E8EE; --muted: #98A3B1; --line: #28313C; --accent: #7DB0FF; --pass: #5DC98C; color-scheme: dark }} }}
:root[data-theme="dark"] {{
  --bg: #0D1116; --surface: #141A21; --fg: #E3E8EE; --muted: #98A3B1; --line: #28313C; --accent: #7DB0FF; --pass: #5DC98C; color-scheme: dark }}
body {{ margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.6 var(--sans); }}
.wrap {{ max-width: 860px; margin: 0 auto; padding-block: 32px 56px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px));
  display: grid; gap: 28px; }}
header {{ display: grid; gap: 8px; }}
.eyebrow {{ font: 500 0.78rem/1.4 var(--mono); color: var(--muted); letter-spacing: 0.04em; text-transform: uppercase; }}
h1 {{ font-size: 2rem; line-height: 1.2; margin: 0; text-wrap: balance; }}
p {{ margin: 0; max-width: 70ch; }}
.list {{ display: grid; gap: 14px; }}
.proof {{ background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 16px 18px; display: grid; gap: 6px; min-width: 0; }}
.proof h2 {{ font-size: 1.15rem; margin: 0; line-height: 1.3; }}
.meta {{ font: 0.8rem/1.4 var(--mono); color: var(--muted); display: flex; gap: 14px; flex-wrap: wrap; font-variant-numeric: tabular-nums; }}
.result {{ font: 0.86rem/1.5 var(--mono); color: var(--pass); }}
.links {{ font-size: 0.9rem; }}
a {{ color: var(--accent); }}
a:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 2px; }}
.empty {{ color: var(--muted); }}
</style></head><body>
<div class="wrap">
  <header>
    <div class="eyebrow">{repo_name} · {n} proof{s}</div>
    <h1>deploy-opencode Proofs</h1>
    <p>End-to-end evidence attached to pull requests: each page carries a recorded run, checks with expected values written before the run, an independent read-back and an audit trail. The scripts and raw results live beside each proof in <a href="{repo}/tree/main/docs/proofs">docs/proofs</a>.</p>
  </header>
  <section class="list" aria-label="Proofs, newest first">{rows}
  </section>
</div>
</body></html>
""".format(repo=esc(repo), repo_name=esc(repo.split("github.com/")[-1]), n=len(rows), s="" if len(rows) == 1 else "s",
           rows="".join(row(m) for m in rows) or '\n    <p class="empty">No proofs published yet.</p>')
open(os.path.join(site, "index.html"), "w").write(page)
print("index.html: %d proof(s)" % len(rows))
