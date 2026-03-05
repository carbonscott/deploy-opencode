# API Key Proxy

A minimal reverse proxy that injects the API key into upstream requests, so users can access the LLM API without reading the key file directly. Users authenticate with a proxy key.

## How it works

```
User on any S3DF node         Proxy on sdfcron001:4000       Stanford AI Gateway
   |                              |                                |
   |-- POST /v1/messages -------->|                                |
   |   + Authorization: proxy-key |                                |
   |                              |  (validates proxy key)         |
   |                              |-- POST /v1/messages ---------->|
   |                              |   + Authorization: Bearer <key>|
   |                              |                                |
   |                              |<-- streaming response ---------|
   |<-- streaming response -------|                                |
```

The proxy validates the incoming proxy key, then replaces it with the real API key before forwarding. Users only know the proxy key, never the API key.

## Quick start on sdfcron001

The proxy runs on sdfcron001 as a persistent service, accessible from any S3DF node.
All commands below can be run from any node — no need to SSH manually.

### 1. Create the proxy key

```bash
mkdir -p proxy/run
echo 'choose-a-secret-proxy-key' > proxy/run/proxy-key.dat
chmod 600 proxy/run/proxy-key.dat
```

### 2. Start the proxy on sdfcron001

```bash
# Start the proxy remotely (runs on sdfcron001, no manual SSH needed)
ssh sdfcron001 "$(pwd)/proxy/scripts/proxy-cron.sh" start

# Verify it's reachable from your current node
curl http://sdfcron001:4000/health
# ok
```

### 3. Enable auto-restart on reboot

```bash
# Adds an @reboot cron entry on sdfcron001 (via SSH)
./proxy/scripts/proxy-cron.sh enable
```

### 4. Manage the proxy

```bash
# Check status (PID, config, cron, recent logs)
./proxy/scripts/proxy-cron.sh status

# Restart
ssh sdfcron001 "$(pwd)/proxy/scripts/proxy-cron.sh" restart

# Stop
ssh sdfcron001 "$(pwd)/proxy/scripts/proxy-cron.sh" stop

# Disable auto-restart
./proxy/scripts/proxy-cron.sh disable
```

### 5. Configure clients

#### OpenCode

In your personal `~/.config/opencode/opencode.json` (not the shared config):

```json
{
  "baseURL": "http://sdfcron001:4000/v1",
  "apiKey": "<your-proxy-key>"
}
```

Then launch opencode without the shared config:

```bash
unset OPENCODE_CONFIG_DIR
opencode
```

#### Claude Code

```bash
export ANTHROPIC_BASE_URL=http://sdfcron001:4000
export ANTHROPIC_API_KEY=<your-proxy-key>
```

Where `<your-proxy-key>` matches the contents of `proxy/run/proxy-key.dat`.

### 6. Health check

The `/health` endpoint returns 200 without requiring authentication:

```bash
curl http://sdfcron001:4000/health
# ok
```

## Configuration

All settings can be overridden via environment variables or `env.local`:

| Variable | Default | Description |
|----------|---------|-------------|
| `PROXY_HOST` | `0.0.0.0` | Listen address |
| `PROXY_PORT` | `4000` | Listen port |
| `PROXY_API_KEY_FILE` | `/sdf/group/lcls/ds/dm/apps/dev/env/key.dat` | Real API key |
| `PROXY_KEY_FILE` | `./run/proxy-key.dat` | Proxy key for client auth |
| `PROXY_PYTHON` | Shared Python 3.11 | Python interpreter |
| `CRON_NODE` | `sdfcron001` | Node for cron job |

## File structure

```
proxy/
├── proxy.py              # The reverse proxy (stdlib only, no deps)
├── env.sh                # Environment setup (sourced by scripts)
├── env.local             # [gitignored] deployment-specific overrides
├── start-proxy.sh        # Convenience: start the proxy
├── stop-proxy.sh         # Convenience: stop the proxy
├── scripts/
│   └── proxy-cron.sh     # Service manager (start/stop/status/enable/disable)
└── run/                  # Runtime state (gitignored)
    ├── proxy.pid
    ├── proxy.log
    └── proxy-key.dat
```

## Limitations

- **No TLS** — proxy listens on plain HTTP. Only safe on the internal S3DF cluster network.
- **Thread-per-request** — uses Python `ThreadingHTTPServer`. Handles concurrent users fine for a small team.
- **Single proxy key** — all users share one proxy key. No per-user tracking or budget enforcement.

## Open question: distributing skills to non-ps-data users

The proxy solves API key access — anyone with the proxy key can call the LLM. But the **agent skills** (elog-copilot, askcode, confluence-doc, etc.) and their data live under `/sdf/group/lcls/ds/dm/apps/dev/`, which is group-owned by `ps-data`. Users outside `ps-data` — other SLAC groups, external collaborators, students — cannot read these files even if they have a proxy key.

This creates a two-tier problem:

1. **API access** (solved by proxy) — anyone with the proxy key can call Claude/GPT
2. **Skill access** (unsolved) — skills need to read local files (SQLite databases, code indexes, documentation) that are restricted to `ps-data`

Possible approaches (not yet decided):

- **ACLs on the skills/data directories** — add individual users or a secondary group with read access via `setfacl`. Simple but doesn't scale well and requires manual management per user.
- **A shared "opencode-users" group** — request IT to create a broader group that includes non-ps-data users. Deployed data gets `chgrp opencode-users`. Clean but requires IT coordination.
- **Publish a "lite" config** — a separate `opencode.json` that only includes the proxy provider (no skills). Non-ps-data users get the LLM but not the specialized agents. Limits utility.
- **Serve skills through the proxy too** — extend the proxy to also serve skill data (SQLite queries, doc search) as API endpoints. Users don't need filesystem access. Significant engineering effort.

For now, non-ps-data users can use the proxy for raw LLM access. Skill distribution is TBD.

## Production path

For per-user tracking and budget control, replace this with **LiteLLM** — which is what Stanford's AI Gateway runs internally. LiteLLM adds per-user virtual keys, spend tracking, rate limiting, and OIDC/SSO support.
