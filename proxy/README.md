# API Key Proxy

A minimal reverse proxy that injects the API key into upstream requests, so users can access the LLM API without reading the key file directly.

## How it works

```
opencode                    proxy (localhost:4000)           Stanford AI Gateway
   |                              |                                |
   |-- POST /v1/messages -------->|                                |
   |   (no API key)               |                                |
   |                              |-- POST /v1/messages ---------->|
   |                              |   + Authorization: Bearer <key>|
   |                              |                                |
   |                              |<-- streaming response ---------|
   |<-- streaming response -------|                                |
```

The proxy reads the API key from the key file at startup and adds it to every request. Users never see the key.

## Usage

```bash
# Start
./proxy/start-proxy.sh

# Stop
./proxy/stop-proxy.sh

# Check logs
tail proxy/run/proxy.log
```

## opencode configuration

Change two fields in your `opencode.json` provider options:

```json
{
  "baseURL": "http://127.0.0.1:4000/v1",
  "apiKey": "proxy"
}
```

Previously these were:

```json
{
  "baseURL": "https://aiapi-prod.stanford.edu/v1",
  "apiKey": "{file:/sdf/group/lcls/ds/dm/apps/dev/env/key.dat}"
}
```

## Limitations

- **Single-threaded** — handles one request at a time (Python `http.server`). Fine for individual use, not for concurrent team access.
- **No TLS** — proxy listens on plain HTTP. Only safe when proxy and client are on the same machine (`127.0.0.1`).

## Production path

For real multi-user deployment, replace this with:

1. **nginx** (rebuild with `--with-http_ssl_module`) or **caddy** — handles concurrency, TLS, and streaming natively
2. **Run as a dedicated service account** — the service account owns the key file (`chmod 600`), regular users cannot read it
3. **LiteLLM** — if you also want per-user virtual keys, spend tracking, and rate limiting
