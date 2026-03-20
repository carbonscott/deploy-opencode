# OpenCode Log Analysis

Ingest OpenCode session logs into DuckDB for structured analysis of API response times, errors, and tool usage.

## Quick Start

```bash
uv run ingest_opencode_logs.py \
  --log-dir ~/.local/share/opencode/log \
  --db opencode_logs.db
```

For sandbox users:
```bash
uv run ingest_opencode_logs.py \
  --log-dir "$SCRATCH/$USER-opencode-sandbox/home/.local/share/opencode/log" \
  --db opencode_logs.db
```

## CLI Options

| Flag | Default | Description |
|------|---------|-------------|
| `--log-dir` | (required) | Directory containing `.log` files |
| `--db` | `opencode_logs.db` | Output DuckDB database path |
| `--glob` | `*.log` | File pattern to match |
| `--replace` | `False` | Drop and recreate tables (default: append) |

## Database Schema

### `log_events` — all parsed log lines

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Auto-increment row ID |
| `timestamp` | TIMESTAMP | Absolute timestamp |
| `delta_ms` | INTEGER | Delta from previous log line (`+Xms` field) |
| `level` | VARCHAR | `INFO` or `ERROR` |
| `service` | VARCHAR | e.g. `llm`, `server`, `bus`, `permission` |
| `message` | VARCHAR | Free-text message after key-value pairs |
| `attributes` | VARCHAR | All key=value pairs as JSON string |
| `log_file` | VARCHAR | Source filename |
| `line_number` | INTEGER | Line number in source file |

### `llm_calls` — one row per LLM streaming call (derived)

| Column | Type | Description |
|--------|------|-------------|
| `call_id` | INTEGER | Auto-increment |
| `timestamp` | TIMESTAMP | When the streaming call started |
| `provider_id` | VARCHAR | e.g. `stanford`, `opencode` |
| `model_id` | VARCHAR | e.g. `claude-4-5-sonnet`, `gpt-5-nano` |
| `session_id` | VARCHAR | Session identifier |
| `agent` | VARCHAR | e.g. `build`, `title`, `elog-copilot` |
| `mode` | VARCHAR | `primary`, `subagent`, or `all` |
| `is_small` | BOOLEAN | Whether this is a "small" model call |
| `first_delta_ts` | TIMESTAMP | First streaming token received |
| `ttft_seconds` | DOUBLE | Time to first token |
| `end_ts` | TIMESTAMP | Next LLM call in same session |
| `turn_duration_seconds` | DOUBLE | Total turn time (includes tool execution) |
| `has_error` | BOOLEAN | Whether an error occurred during this call |
| `log_file` | VARCHAR | Source filename |

## Example Queries

```sql
-- TTFT statistics by model and agent
SELECT model_id, agent, count(*) as n,
       round(avg(ttft_seconds), 2) as avg_ttft,
       round(median(ttft_seconds), 2) as med_ttft,
       round(quantile_cont(ttft_seconds, 0.95), 2) as p95_ttft
FROM llm_calls
WHERE ttft_seconds IS NOT NULL
GROUP BY model_id, agent
ORDER BY n DESC;

-- Error summary
SELECT timestamp, model_id, agent, log_file
FROM llm_calls
WHERE has_error
ORDER BY timestamp;

-- All errors with details
SELECT timestamp, service, message,
       json_extract_string(attributes, '$.error') as error
FROM log_events
WHERE level = 'ERROR'
ORDER BY timestamp;

-- Service activity breakdown
SELECT service, count(*) as n
FROM log_events
GROUP BY service
ORDER BY n DESC;

-- Calls per session
SELECT session_id, count(*) as n_calls,
       round(avg(ttft_seconds), 1) as avg_ttft,
       sum(CASE WHEN has_error THEN 1 ELSE 0 END) as errors
FROM llm_calls
GROUP BY session_id
ORDER BY n_calls DESC;
```

## How It Works

The script parses OpenCode's structured log format:
```
INFO  2026-03-17T03:40:19 +5ms service=llm providerID=stanford modelID=claude-4-5-sonnet ...
```

1. **Parse**: Regex extracts level, timestamp, delta, and key=value pairs from each line. Multi-line entries (continuation lines starting with whitespace) are merged.
2. **Load**: All entries go into `log_events` via batch inserts.
3. **Derive**: `llm_calls` is computed with SQL window functions — matching each `service=llm ... stream` event to its first `message.part.delta` (for TTFT) and next stream call (for turn duration).
