# Self-Serve: confluence-doc

Export LCLS Confluence documentation to a SQLite database for use with the `confluence-doc` agent.

## Prerequisites

- SLAC Confluence access (most employees have this)
- SDF account

## Quick Start

### 1. Generate a Confluence API Token

1. Go to https://confluence.slac.stanford.edu
2. Click your profile icon → **Settings** → **Personal Access Tokens**
3. Create a new token with read access
4. Save the token to a file (keep it private):

```bash
mkdir -p ~/.config/confluence
echo "YOUR_TOKEN_HERE" > ~/.config/confluence/token.dat
chmod 600 ~/.config/confluence/token.dat
```

### 2. Set Up Your Local Copy

```bash
# Choose where to store your data
export MY_CONFLUENCE_DIR="$HOME/confluence-doc"
mkdir -p "$MY_CONFLUENCE_DIR"

# Copy the tool
cp -r /sdf/group/lcls/ds/dm/apps/dev/tools/confluence-doc/* "$MY_CONFLUENCE_DIR/"

# Create env.local with your settings
cat > "$MY_CONFLUENCE_DIR/env.local" << 'EOF'
export CONFLUENCE_TOKEN_FILE="$HOME/.config/confluence/token.dat"
export CONFLUENCE_DOC_DATA_DIR="$HOME/confluence-doc"
EOF
```

### 3. Create the Virtual Environment

```bash
cd "$MY_CONFLUENCE_DIR"
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
deactivate
```

### 4. Run the Export

```bash
cd "$MY_CONFLUENCE_DIR"
./scripts/confluence-cron.sh test    # Dry run to verify config
./scripts/confluence-cron.sh run     # Full export (takes ~30 min first time)
```

This creates:
- `confluence_export/` — Markdown files
- `lcls-docs.db` — SQLite database with FTS5 search

### 5. Query Your Database

```bash
# Count documents
sqlite3 "$MY_CONFLUENCE_DIR/lcls-docs.db" "SELECT COUNT(*) FROM documents"

# Search for a topic
sqlite3 -header -column "$MY_CONFLUENCE_DIR/lcls-docs.db" \
  "SELECT title, url FROM documents WHERE title LIKE '%psana%' LIMIT 10"

# Full-text search
sqlite3 -header -column "$MY_CONFLUENCE_DIR/lcls-docs.db" \
  "SELECT title, snippet(documents_fts, 2, '→', '←', '...', 30) as match
   FROM documents_fts WHERE documents_fts MATCH 'detector calibration'
   LIMIT 10"
```

## Configuration Options

Edit `env.local` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `CONFLUENCE_TOKEN_FILE` | (required) | Path to your API token file |
| `CONFLUENCE_DOC_DATA_DIR` | Same as app dir | Where to store exports and database |
| `CONFLUENCE_SPACE` | `PSDM` | Confluence space to export |
| `CONFLUENCE_URL` | `https://confluence.slac.stanford.edu` | Confluence server URL |
| `EXPORT_DELAY` | `0.2` | Seconds between API requests (be nice to the server) |

### Exporting a Different Space

To export a different Confluence space:

```bash
# In env.local
export CONFLUENCE_SPACE="PCDS"  # or any space key you have access to
```

## Automation (Optional)

If you want your database to stay current:

```bash
# Check current status
./scripts/confluence-cron.sh status

# Enable hourly updates (runs on sdfcron001)
./scripts/confluence-cron.sh enable

# Disable when done
./scripts/confluence-cron.sh disable
```

Logs are written to `$CONFLUENCE_DOC_DATA_DIR/cron.log`.

## Using with Your Own Agent

Create an agent that points to your database:

```markdown
# My Confluence Agent

Search documentation in my local Confluence export.

## Database

Query with sqlite3:

\`\`\`bash
sqlite3 -header -column "$HOME/confluence-doc/lcls-docs.db" "YOUR SQL HERE"
\`\`\`

## Schema

| Table | Columns |
|-------|---------|
| documents | id, title, url, content, space_key, last_modified |
| documents_fts | FTS5 virtual table for full-text search |
```

## Troubleshooting

**"Token file not found"**
- Check `CONFLUENCE_TOKEN_FILE` path in env.local
- Ensure the file exists and is readable

**"401 Unauthorized"**
- Your token may have expired — generate a new one
- Verify you have access to the target Confluence space

**"Rate limited"**
- Increase `EXPORT_DELAY` in env.local (e.g., `0.5`)

**First export is slow**
- Initial export downloads all pages (~30 min for PSDM space)
- Subsequent runs use `--resume` and only fetch new/changed pages
