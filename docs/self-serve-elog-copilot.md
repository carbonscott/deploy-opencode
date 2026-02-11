# Self-Serve: elog-copilot

Build your own elog SQLite database for use with the `elog-copilot` agent.

## Prerequisites

- SLAC Kerberos credentials (all employees have this)
- SDF account

## Quick Start

### 1. Verify Kerberos Access

```bash
# Get a Kerberos ticket (enter your SLAC password)
kinit YOUR_USERNAME@SLAC.STANFORD.EDU

# Verify it worked
klist
```

### 2. Set Up Your Local Copy

```bash
# Choose where to store your data
export MY_ELOG_DIR="$HOME/elog-copilot"
mkdir -p "$MY_ELOG_DIR"

# Copy the tool
cp -r /sdf/group/lcls/ds/dm/apps/dev/tools/elog-copilot/* "$MY_ELOG_DIR/"

# Create env.local with your settings
cat > "$MY_ELOG_DIR/env.local" << EOF
export KRB5_PRINCIPAL="${USER}@SLAC.STANFORD.EDU"
export ELOG_COPILOT_DATA_DIR="$HOME/elog-copilot"
EOF
```

### 3. Create the Virtual Environment

The tool requires a special Python with Kerberos support:

```bash
cd "$MY_ELOG_DIR"

# Use the conda Python with krtc (Kerberos)
export UV_PYTHON="/sdf/group/lcls/ds/ana/sw/conda1/inst/envs/ana-4.0.62-py3/bin/python"

# Create venv and install
python -m venv .venv
source .venv/bin/activate
pip install -e .
deactivate
```

### 4. Run the Export

```bash
# Ensure you have a valid Kerberos ticket
kinit

cd "$MY_ELOG_DIR"
./scripts/elog-cron.sh test    # Dry run to verify config
./scripts/elog-cron.sh run     # Full export
```

This creates:
- `elog_YYYYMMDD_HHMMSS.db` — Timestamped SQLite database
- `elog-copilot.db` — Symlink to the latest database

### 5. Query Your Database

```bash
DB="$MY_ELOG_DIR/elog-copilot.db"

# List experiments
sqlite3 -header -column "$DB" "SELECT name, instrument FROM experiments LIMIT 10"

# Find runs for an experiment
sqlite3 -header -column "$DB" \
  "SELECT run_num, begin_time, end_time
   FROM runs WHERE experiment = 'mfxx12345'
   ORDER BY run_num LIMIT 10"

# Search logbook entries
sqlite3 -header -column "$DB" \
  "SELECT experiment, run_num, substr(content, 1, 100) as preview
   FROM elog_entries WHERE content LIKE '%alignment%' LIMIT 10"
```

## Configuration Options

Edit `env.local` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `KRB5_PRINCIPAL` | (required) | Your Kerberos principal (user@SLAC.STANFORD.EDU) |
| `ELOG_COPILOT_DATA_DIR` | Same as app dir | Where to store databases |
| `HOURS_LOOKBACK` | `168` (1 week) | How far back to fetch data |
| `PARALLEL_JOBS` | `10` | Concurrent fetch requests |
| `KEEP_DB_COUNT` | `8` | Number of old databases to retain |
| `KRB5_PASSWORD_FILE` | (optional) | For unattended cron — see below |

### Fetching More History

To fetch more than 1 week of data:

```bash
# In env.local
export HOURS_LOOKBACK=720  # 30 days
```

Or as a one-time override:

```bash
HOURS_LOOKBACK=720 ./scripts/elog-cron.sh run
```

## Automation (Optional)

For automated updates, you need unattended Kerberos authentication.

### Setting Up Unattended Kerberos

1. Create a password file (keep it secure):

```bash
mkdir -p ~/.config/kerberos
echo "YOUR_PASSWORD" > ~/.config/kerberos/password.dat
chmod 600 ~/.config/kerberos/password.dat
```

2. Add to env.local:

```bash
export KRB5_PASSWORD_FILE="$HOME/.config/kerberos/password.dat"
```

3. Enable cron:

```bash
./scripts/elog-cron.sh status   # Check current state
./scripts/elog-cron.sh enable   # Enable 6-hourly updates on sdfcron001
./scripts/elog-cron.sh disable  # Disable when done
```

Logs are written to `$ELOG_COPILOT_DATA_DIR/cron.log`.

## Using with Your Own Agent

Create an agent that points to your database:

```markdown
# My Elog Agent

Query LCLS experiment elog data from my local database.

## Database

\`\`\`bash
sqlite3 -header -column "$HOME/elog-copilot/elog-copilot.db" "YOUR SQL HERE"
\`\`\`

## Key Tables

| Table | Description |
|-------|-------------|
| experiments | Experiment metadata (name, instrument, dates) |
| runs | Run numbers with timestamps |
| elog_entries | Logbook entries with content |
| detectors | Detector configurations per run |
| samples | Sample information |
```

## Troubleshooting

**"No valid Kerberos ticket"**
- Run `kinit YOUR_USERNAME@SLAC.STANFORD.EDU`
- For cron, ensure `KRB5_PASSWORD_FILE` is set and readable

**"Permission denied" or "Authentication failed"**
- Your Kerberos ticket may have expired — run `kinit` again
- Verify your principal is correct: `klist`

**"ModuleNotFoundError: krtc"**
- The venv must use the conda Python with Kerberos support
- Ensure `UV_PYTHON` points to the ana environment

**Database is small or missing data**
- Increase `HOURS_LOOKBACK` to fetch more history
- Check `cron.log` for errors during fetch

**Old databases piling up**
- Adjust `KEEP_DB_COUNT` in env.local
- Old databases are automatically cleaned up after each run
