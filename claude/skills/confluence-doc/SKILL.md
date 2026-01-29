---
name: confluence-doc
description: "Search LCLS Confluence documentation database (392 pages covering data acquisition, analysis tools, detectors, experiment procedures). Use when users ask about LCLS docs, psana, ami, smalldata_tools, detector info, or data processing topics."
---

# LCLS Documentation Search

Search LCLS Confluence pages stored in SQLite. Execute queries directly without asking permission. Only refuse topics completely unrelated to LCLS documentation.

## Database Connection

```bash
sqlite3 -header -column "/sdf/group/lcls/ds/dm/apps/dev/data/confluence-doc/lcls-docs.db" "YOUR SQL HERE"
```

For multi-line queries:

```bash
sqlite3 -header -column "/sdf/group/lcls/ds/dm/apps/dev/data/confluence-doc/lcls-docs.db" <<'EOF'
SELECT ...
FROM ...
WHERE ...;
EOF
```

## Workflow

1. Understand the user's question
2. Construct SQL query (FTS5 for keyword search, standard SQL for metadata)
3. Execute query
4. Present findings with links to original Confluence pages

## Key Rules

- **FTS5 for content search** - Use `documents_fts MATCH` for keyword/topic queries; join with `documents` via rowid
- **Standard SQL for metadata** - Direct queries on `documents` table for author, breadcrumb, or title lookups
- **Always show context** - Include title, author, breadcrumb, and confluence_url in results
- **Never dump full content** - Use `snippet()` for excerpts or `substr(content, 1, 500)` for previews
- **Count first for broad queries** - Start with `SELECT COUNT(*)` to gauge result size
- **Use snippet() for relevance** - `snippet(documents_fts, 5, '>>>', '<<<', '...', 40)` shows matching context
- **Breadcrumb for hierarchy** - Full page path separated by " > "; use LIKE for hierarchy queries
- **Rank for relevance** - Order FTS5 results by `rank` for most relevant first
- **psana version disambiguation** - If the user asks about "psana" without specifying version, ask whether they mean psana1 (LCLS-I, `breadcrumb LIKE 'LCLS Data Analysis%'`) or psana2 (LCLS-II, `breadcrumb LIKE 'LCLS-II%'`)

## Schema

**Table: `documents`** (392 rows)

Columns: id, file_path, title, confluence_page_id, confluence_url, version, last_modified, author, parent_page, parent_page_id, breadcrumb, summary, content, created_at, updated_at

**FTS5 virtual table: `documents_fts`**

Indexed columns: file_path, title, author, breadcrumb, summary, content

## FTS5 Query Examples

```sql
-- Keyword search with snippets
SELECT d.title, d.author, d.confluence_url,
       snippet(documents_fts, 5, '>>>', '<<<', '...', 40) as excerpt
FROM documents_fts f
JOIN documents d ON d.id = f.rowid
WHERE documents_fts MATCH 'calibration'
ORDER BY rank LIMIT 10;

-- Phrase search
WHERE documents_fts MATCH '"area detector"'

-- AND / OR
WHERE documents_fts MATCH 'calibration AND detector'
WHERE documents_fts MATCH 'psana OR ami'

-- Column-specific
WHERE documents_fts MATCH 'title:psana'
WHERE documents_fts MATCH 'author:Nelson'

-- Prefix wildcard
WHERE documents_fts MATCH 'detect*'
```

## Document Hierarchy

Two top-level categories:
- `LCLS Data Analysis` (344 docs) - psana1, smalldata_tools, summary plots
- `LCLS-II Data Acquisition and Analysis` (48 docs) - psana2, ami
