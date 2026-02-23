#!/usr/bin/env python3
"""Minimal reverse proxy that injects an API key into upstream requests.

Listens on localhost:4000 and forwards all requests to the Stanford AI Gateway,
adding the Authorization header so users never need the key.
"""

import http.server
import http.client
import ssl
import sys
import threading
from pathlib import Path

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 4000
UPSTREAM_HOST = "aiapi-prod.stanford.edu"
UPSTREAM_PORT = 443
KEY_FILE = "/sdf/group/lcls/ds/dm/apps/dev/env/key.dat"


def load_api_key():
    key = Path(KEY_FILE).read_text().strip()
    if not key:
        print(f"Error: empty key file: {KEY_FILE}", file=sys.stderr)
        sys.exit(1)
    return key


API_KEY = load_api_key()
SSL_CTX = ssl.create_default_context(cafile="/etc/pki/tls/certs/ca-bundle.crt")


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_request(self):
        # Read request body if present
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length else None

        # Connect to upstream
        conn = http.client.HTTPSConnection(UPSTREAM_HOST, UPSTREAM_PORT, context=SSL_CTX)

        # Build headers — forward originals, override auth
        headers = {}
        for key, val in self.headers.items():
            lower = key.lower()
            if lower in ("host", "authorization"):
                continue
            headers[key] = val
        headers["Host"] = UPSTREAM_HOST
        headers["Authorization"] = f"Bearer {API_KEY}"

        try:
            conn.request(self.command, self.path, body=body, headers=headers)
            upstream_resp = conn.getresponse()

            # Send status
            self.send_response_only(upstream_resp.status)

            # Forward response headers
            for key, val in upstream_resp.getheaders():
                if key.lower() == "transfer-encoding":
                    continue  # let us handle chunking
                self.send_header(key, val)
            self.end_headers()

            # Stream response body
            while True:
                chunk = upstream_resp.read(4096)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except Exception as e:
            self.send_error(502, f"Upstream error: {e}")
        finally:
            conn.close()

    # Handle all HTTP methods
    do_GET = do_request
    do_POST = do_request
    do_PUT = do_request
    do_DELETE = do_request
    do_PATCH = do_request
    do_OPTIONS = do_request

    def log_message(self, format, *args):
        print(f"[proxy] {self.address_string()} - {format % args}", flush=True)


def main():
    server = http.server.HTTPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler)
    print(f"Proxy listening on http://{LISTEN_HOST}:{LISTEN_PORT}")
    print(f"Forwarding to https://{UPSTREAM_HOST} (key injected)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nProxy stopped")
        server.server_close()


if __name__ == "__main__":
    main()
