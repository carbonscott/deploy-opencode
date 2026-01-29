# Confluence Documentation Database Schema

## documents table

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER | PK |
| file_path | TEXT | Local file path |
| title | TEXT | Page title |
| confluence_page_id | TEXT | Confluence page ID |
| confluence_url | TEXT | URL to original page |
| version | INTEGER | Page version |
| last_modified | TEXT | Last modification date |
| author | TEXT | Page author |
| parent_page | TEXT | Parent page title |
| parent_page_id | TEXT | Parent page ID |
| breadcrumb | TEXT | Full path separated by " > " |
| summary | TEXT | Page summary |
| content | TEXT | Full page content |
| created_at | DATETIME | |
| updated_at | DATETIME | |

## documents_fts (FTS5 virtual table)

Full-text search index on: file_path, title, author, breadcrumb, summary, content

## Query Patterns

### Basic keyword search

```sql
SELECT d.title, d.author, d.confluence_url,
       snippet(documents_fts, 5, '>>>', '<<<', '...', 40) as excerpt
FROM documents_fts f
JOIN documents d ON d.id = f.rowid
WHERE documents_fts MATCH 'keyword'
ORDER BY rank LIMIT 10;
```

### Phrase search

```sql
WHERE documents_fts MATCH '"exact phrase"'
```

### Boolean operators

```sql
WHERE documents_fts MATCH 'term1 AND term2'
WHERE documents_fts MATCH 'term1 OR term2'
WHERE documents_fts MATCH 'term1 NOT term2'
```

### Column-specific search

```sql
WHERE documents_fts MATCH 'title:psana'
WHERE documents_fts MATCH 'author:Nelson'
WHERE documents_fts MATCH 'breadcrumb:detector'
```

### Prefix wildcard

```sql
WHERE documents_fts MATCH 'detect*'
```

### Hierarchy queries (using breadcrumb)

```sql
-- psana1 docs (LCLS-I)
WHERE breadcrumb LIKE 'LCLS Data Analysis%'

-- psana2 docs (LCLS-II)
WHERE breadcrumb LIKE 'LCLS-II%'

-- All detector docs
WHERE breadcrumb LIKE '%Detectors%'
```

## Document Categories

| Top-level | Count | Topics |
|-----------|-------|--------|
| LCLS Data Analysis | 344 | psana1, smalldata_tools, summary plots |
| LCLS-II Data Acquisition and Analysis | 48 | psana2, ami |

## psana Version Disambiguation

When users ask about "psana" without specifying version:
- **psana1 (LCLS-I):** 160 docs under `LCLS Data Analysis > psana`
- **psana2 (LCLS-II):** 10 docs under `LCLS-II Data Acquisition and Analysis > psana`

Ask user to clarify which version they need.
