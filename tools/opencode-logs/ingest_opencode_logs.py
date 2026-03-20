# /// script
# requires-python = ">=3.9"
# dependencies = ["duckdb"]
# ///
"""Ingest OpenCode log files into a DuckDB database for analysis."""

import argparse
import glob
import json
import os
import re
from datetime import datetime

import duckdb

# Regex for primary log lines:
# INFO  2026-03-17T03:40:19 +5ms service=llm ...
LOG_LINE_RE = re.compile(
    r"^(INFO|ERROR|WARN|FATAL)\s+"
    r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s+"
    r"\+(\d+)ms\s+"
    r"(.*)"
)

# Key=value pairs in the remainder. Handles:
#   simple:  key=value
#   quoted:  key="value with spaces"
#   json:    key={...} or key=[...]
# The tricky part is error= fields that contain huge JSON blobs or free text.
# Strategy: greedily match known keys, treat the last unkeyed text as message.
KNOWN_KEYS = [
    "service", "status", "duration", "method", "path", "type",
    "providerID", "modelID", "sessionID", "agent", "mode", "small",
    "name", "directory", "count", "id", "parentID", "projectID",
    "permission", "pattern", "ruleset", "action", "kind", "file",
    "hash", "slug", "step", "total", "results", "resolved",
    "target", "version", "pkg", "platform", "backend", "branch",
    "url", "query", "key", "mime", "shell", "time", "token",
    "title", "prune", "pruned", "serverIds", "serverID", "arg",
    "cmd", "cwd", "code", "stdout", "stderr",
]

# Build a pattern that matches key=value where value can be:
#   - a JSON object/array (brace/bracket matched)
#   - a quoted string
#   - a simple token (no spaces, up to next key= or end)
_key_alt = "|".join(re.escape(k) for k in KNOWN_KEYS)
# We'll parse key=value pairs procedurally instead of with one big regex,
# because values like error={huge json} or stdout=multiline are too complex.


def parse_kv_and_message(remainder: str) -> tuple[dict, str]:
    """Parse key=value pairs from the remainder of a log line.

    Returns (attributes_dict, trailing_message).
    """
    attrs = {}
    pos = 0
    last_value_end = 0
    remainder_len = len(remainder)

    while pos < remainder_len:
        # Look for next key= pattern
        match = re.search(r"\b([a-zA-Z_][a-zA-Z0-9_.]*?)=", remainder[pos:])
        if not match:
            break

        key_start = pos + match.start()
        key = match.group(1)
        value_start = pos + match.end()

        if value_start >= remainder_len:
            attrs[key] = ""
            pos = remainder_len
            last_value_end = pos
            break

        char = remainder[value_start]

        if char == '"':
            # Quoted value — find closing quote
            end = remainder.find('"', value_start + 1)
            if end == -1:
                end = remainder_len
            value = remainder[value_start + 1 : end]
            pos = end + 1
        elif char in "{[":
            # JSON value — brace/bracket match
            depth = 0
            i = value_start
            open_char = char
            close_char = "}" if char == "{" else "]"
            while i < remainder_len:
                c = remainder[i]
                if c == open_char:
                    depth += 1
                elif c == close_char:
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            value = remainder[value_start : i + 1]
            pos = i + 1
        elif key == "error":
            # error= consumes everything to end of line (it's always last
            # or contains embedded key=value that aren't real keys)
            value = remainder[value_start:].rstrip()
            pos = remainder_len
        else:
            # Simple value — up to next space
            space = remainder.find(" ", value_start)
            if space == -1:
                value = remainder[value_start:]
                pos = remainder_len
            else:
                value = remainder[value_start:space]
                pos = space + 1

        attrs[key] = value
        last_value_end = pos

    # Trailing message is whatever comes after the last key=value
    message = remainder[last_value_end:].strip()

    return attrs, message


def parse_log_file(filepath: str):
    """Parse a single log file, yielding (line_number, level, timestamp, delta_ms, service, message, attributes_json) tuples."""
    basename = os.path.basename(filepath)
    current_entry = None

    with open(filepath, "r", errors="replace") as f:
        for line_num, line in enumerate(f, 1):
            line = line.rstrip("\n")
            m = LOG_LINE_RE.match(line)
            if m:
                # Emit previous entry if any
                if current_entry is not None:
                    yield current_entry

                level, ts_str, delta_str, remainder = m.groups()
                attrs, message = parse_kv_and_message(remainder)
                service = attrs.pop("service", "")

                current_entry = (
                    line_num,
                    level,
                    ts_str,
                    int(delta_str),
                    service,
                    message,
                    json.dumps(attrs) if attrs else "{}",
                    basename,
                )
            elif current_entry is not None:
                # Continuation line — append to previous entry's message
                prev = list(current_entry)
                prev[5] = prev[5] + "\n" + line.strip() if prev[5] else line.strip()
                current_entry = tuple(prev)
            # else: orphan continuation line before any entry, skip

    # Emit last entry
    if current_entry is not None:
        yield current_entry


def create_tables(db: duckdb.DuckDBPyConnection, replace: bool):
    if replace:
        db.execute("DROP TABLE IF EXISTS llm_calls")
        db.execute("DROP TABLE IF EXISTS log_events")

    db.execute("""
        CREATE TABLE IF NOT EXISTS log_events (
            id          INTEGER PRIMARY KEY DEFAULT(nextval('log_events_seq')),
            timestamp   TIMESTAMP NOT NULL,
            delta_ms    INTEGER,
            level       VARCHAR,
            service     VARCHAR,
            message     VARCHAR,
            attributes  VARCHAR,
            log_file    VARCHAR,
            line_number INTEGER
        )
    """)

    db.execute("""
        CREATE TABLE IF NOT EXISTS llm_calls (
            call_id              INTEGER PRIMARY KEY DEFAULT(nextval('llm_calls_seq')),
            timestamp            TIMESTAMP NOT NULL,
            provider_id          VARCHAR,
            model_id             VARCHAR,
            session_id           VARCHAR,
            agent                VARCHAR,
            mode                 VARCHAR,
            is_small             BOOLEAN,
            first_delta_ts       TIMESTAMP,
            ttft_seconds         DOUBLE,
            end_ts               TIMESTAMP,
            turn_duration_seconds DOUBLE,
            has_error            BOOLEAN,
            log_file             VARCHAR
        )
    """)


def create_sequences(db: duckdb.DuckDBPyConnection, replace: bool):
    if replace:
        db.execute("DROP SEQUENCE IF EXISTS log_events_seq")
        db.execute("DROP SEQUENCE IF EXISTS llm_calls_seq")
    db.execute("CREATE SEQUENCE IF NOT EXISTS log_events_seq START 1")
    db.execute("CREATE SEQUENCE IF NOT EXISTS llm_calls_seq START 1")


def ingest_files(db: duckdb.DuckDBPyConnection, log_files: list[str]):
    total_lines = 0
    total_entries = 0

    for filepath in sorted(log_files):
        basename = os.path.basename(filepath)
        batch = []
        entry_count = 0

        for entry in parse_log_file(filepath):
            batch.append(entry)
            entry_count += 1

            if len(batch) >= 5000:
                _insert_batch(db, batch)
                batch = []

        if batch:
            _insert_batch(db, batch)

        file_lines = sum(1 for _ in open(filepath, errors="replace"))
        total_lines += file_lines
        total_entries += entry_count
        print(f"  {basename}: {file_lines} lines -> {entry_count} entries")

    return total_lines, total_entries


def _insert_batch(db: duckdb.DuckDBPyConnection, batch: list):
    db.executemany(
        """
        INSERT INTO log_events (line_number, level, timestamp, delta_ms, service, message, attributes, log_file)
        VALUES (?, ?, CAST(? AS TIMESTAMP), ?, ?, ?, ?, ?)
        """,
        batch,
    )


def derive_llm_calls(db: duckdb.DuckDBPyConnection):
    """Populate llm_calls table from log_events using SQL."""
    db.execute("DELETE FROM llm_calls")
    db.execute("""
        INSERT INTO llm_calls (
            timestamp, provider_id, model_id, session_id, agent, mode,
            is_small, first_delta_ts, ttft_seconds, end_ts,
            turn_duration_seconds, has_error, log_file
        )
        WITH stream_calls AS (
            SELECT
                id,
                timestamp,
                json_extract_string(attributes, '$.providerID') AS provider_id,
                json_extract_string(attributes, '$.modelID')    AS model_id,
                json_extract_string(attributes, '$.sessionID')  AS session_id,
                json_extract_string(attributes, '$.agent')      AS agent,
                json_extract_string(attributes, '$.mode')       AS mode,
                CASE WHEN json_extract_string(attributes, '$.small') = 'true'
                     THEN true ELSE false END AS is_small,
                log_file,
                LEAD(timestamp) OVER (
                    PARTITION BY json_extract_string(attributes, '$.sessionID')
                    ORDER BY timestamp, id
                ) AS next_stream_ts
            FROM log_events
            WHERE service = 'llm'
              AND message LIKE '%stream%'
        ),
        -- Pre-filter delta events (service=bus only, safe to parse)
        delta_events AS (
            SELECT id, timestamp
            FROM log_events
            WHERE service = 'bus'
              AND json_extract_string(attributes, '$.type') = 'message.part.delta'
        ),
        -- Pre-filter error events
        error_events AS (
            SELECT id, timestamp
            FROM log_events
            WHERE level = 'ERROR'
        ),
        first_deltas AS (
            SELECT
                sc.id AS call_id,
                MIN(de.timestamp) AS first_delta_ts
            FROM stream_calls sc
            LEFT JOIN delta_events de
                ON de.timestamp >= sc.timestamp
                AND de.timestamp <= COALESCE(sc.next_stream_ts, sc.timestamp + INTERVAL '10 minutes')
            GROUP BY sc.id
        ),
        errors AS (
            SELECT
                sc.id AS call_id,
                COUNT(ee.id) > 0 AS has_error
            FROM stream_calls sc
            LEFT JOIN error_events ee
                ON ee.timestamp >= sc.timestamp
                AND ee.timestamp <= COALESCE(sc.next_stream_ts, sc.timestamp + INTERVAL '10 minutes')
            GROUP BY sc.id
        )
        SELECT
            sc.timestamp,
            sc.provider_id,
            sc.model_id,
            sc.session_id,
            sc.agent,
            sc.mode,
            sc.is_small,
            fd.first_delta_ts,
            CASE WHEN fd.first_delta_ts IS NOT NULL
                 THEN EXTRACT(EPOCH FROM fd.first_delta_ts - sc.timestamp)
                 ELSE NULL END AS ttft_seconds,
            sc.next_stream_ts AS end_ts,
            CASE WHEN sc.next_stream_ts IS NOT NULL
                 THEN EXTRACT(EPOCH FROM sc.next_stream_ts - sc.timestamp)
                 ELSE NULL END AS turn_duration_seconds,
            COALESCE(e.has_error, false) AS has_error,
            sc.log_file
        FROM stream_calls sc
        LEFT JOIN first_deltas fd ON fd.call_id = sc.id
        LEFT JOIN errors e ON e.call_id = sc.id
        ORDER BY sc.timestamp
    """)


def print_summary(db: duckdb.DuckDBPyConnection):
    event_count = db.execute("SELECT count(*) FROM log_events").fetchone()[0]
    call_count = db.execute("SELECT count(*) FROM llm_calls").fetchone()[0]
    error_count = db.execute("SELECT count(*) FROM llm_calls WHERE has_error").fetchone()[0]
    print(f"\nSummary:")
    print(f"  log_events: {event_count} rows")
    print(f"  llm_calls:  {call_count} rows ({error_count} with errors)")

    if call_count > 0:
        print(f"\n  LLM calls by model/agent:")
        rows = db.execute("""
            SELECT model_id, agent, count(*) as n,
                   round(avg(ttft_seconds), 2) as avg_ttft,
                   round(median(ttft_seconds), 2) as med_ttft
            FROM llm_calls
            GROUP BY model_id, agent
            ORDER BY n DESC
        """).fetchall()
        print(f"  {'model':<25} {'agent':<15} {'count':>5} {'avg_ttft':>10} {'med_ttft':>10}")
        for row in rows:
            model, agent, n, avg_t, med_t = row
            avg_s = f"{avg_t:.2f}s" if avg_t is not None else "N/A"
            med_s = f"{med_t:.2f}s" if med_t is not None else "N/A"
            print(f"  {model or 'N/A':<25} {agent or 'N/A':<15} {n:>5} {avg_s:>10} {med_s:>10}")


def main():
    parser = argparse.ArgumentParser(
        description="Ingest OpenCode log files into DuckDB for analysis."
    )
    parser.add_argument(
        "--log-dir", required=True, help="Directory containing .log files"
    )
    parser.add_argument(
        "--db", default="opencode_logs.db", help="Output DuckDB database path (default: opencode_logs.db)"
    )
    parser.add_argument(
        "--glob", default="*.log", dest="file_glob", help="File glob pattern (default: *.log)"
    )
    parser.add_argument(
        "--replace", action="store_true", help="Drop and recreate tables before ingestion"
    )
    args = parser.parse_args()

    log_files = sorted(glob.glob(os.path.join(args.log_dir, args.file_glob)))
    if not log_files:
        print(f"No files matching '{args.file_glob}' in {args.log_dir}")
        return 1

    print(f"Found {len(log_files)} log file(s)")

    db = duckdb.connect(args.db)
    create_sequences(db, args.replace)
    create_tables(db, args.replace)

    print("Ingesting log events...")
    total_lines, total_entries = ingest_files(db, log_files)
    print(f"Parsed {total_lines} lines into {total_entries} log entries")

    print("Deriving llm_calls...")
    derive_llm_calls(db)

    print_summary(db)
    db.close()
    print(f"\nDatabase written to: {args.db}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
