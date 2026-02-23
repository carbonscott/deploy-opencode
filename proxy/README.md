# API Key Proxy

A minimal reverse proxy that injects the API key into upstream requests, so users can access the LLM API without reading the key file directly. Requires a proxy key for access control.

## How it works

```
opencode                    proxy (localhost:4000)           Stanford AI Gateway
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

## Setup

### 1. Create the proxy key

```bash
mkdir -p proxy/run
echo 'choose-a-secret-proxy-key' > proxy/run/proxy-key.dat
chmod 600 proxy/run/proxy-key.dat
```

### 2. Start the proxy

```bash
./proxy/start-proxy.sh

# Stop
./proxy/stop-proxy.sh

# Check logs
tail proxy/run/proxy.log
```

### 3. Configure opencode

Change two fields in your `opencode.json` provider options:

```json
{
  "baseURL": "http://127.0.0.1:4000/v1",
  "apiKey": "<your-proxy-key>"
}
```

Where `<your-proxy-key>` matches the contents of `proxy/run/proxy-key.dat`.

Previously these were:

```json
{
  "baseURL": "https://aiapi-prod.stanford.edu/v1",
  "apiKey": "{file:/sdf/group/lcls/ds/dm/apps/dev/env/key.dat}"
}
```

## Limitations

- **No TLS** — proxy listens on plain HTTP. Only safe when proxy and client are on the same machine (`127.0.0.1`).
- **Thread-per-request** — uses Python `ThreadingHTTPServer`. Handles concurrent users fine for a small team, but not high-throughput production workloads.

## Production path

For real multi-user deployment, replace this with:

1. **nginx** (rebuild with `--with-http_ssl_module`) or **caddy** — handles concurrency, TLS, and streaming natively
2. **Run as a dedicated service account** — the service account owns the key file (`chmod 600`), regular users cannot read it
3. **LiteLLM** — if you also want per-user virtual keys, spend tracking, and rate limiting
