"""
IPython Bridge Server - enables remote command execution.

Usage in IPython:
    %run ipython_bridge.py
    # Or: from ipython_bridge import start_bridge; start_bridge()

Then from Claude Code (after SSH tunnel):
    echo '{"code": "1+1"}' | nc localhost 9999
"""
import json
import socket
import sys
import threading
from io import StringIO

_bridge_instance = None


class IPythonBridge:
    """
    Socket server that accepts JSON commands and executes them in IPython.

    Runs in a background thread, listening on localhost only for security.
    """

    def __init__(self, ipython, port=9999):
        self.ipython = ipython
        self.port = port
        self.running = False
        self.server = None

    def start(self):
        """Start the bridge server in a background thread."""
        self.running = True
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(('localhost', self.port))  # localhost only for security
        self.server.listen(5)
        self.server.settimeout(1.0)  # Allow periodic checks for shutdown

        thread = threading.Thread(target=self._serve, daemon=True)
        thread.start()
        print(f"IPython bridge listening on localhost:{self.port}")

    def stop(self):
        """Stop the bridge server."""
        self.running = False
        if self.server:
            self.server.close()
        print("IPython bridge stopped")

    def _serve(self):
        """Main server loop - accepts connections and spawns handlers."""
        while self.running:
            try:
                conn, addr = self.server.accept()
                threading.Thread(
                    target=self._handle,
                    args=(conn,),
                    daemon=True
                ).start()
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"Bridge error: {e}")

    def _handle(self, conn):
        """Handle a single client connection."""
        try:
            # Read request (newline-terminated JSON)
            data = b''
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
                if b'\n' in data:
                    break

            request = json.loads(data.decode())
            response = self._execute(request)
            conn.send(json.dumps(response).encode() + b'\n')
        except Exception as e:
            error_resp = {'status': 'error', 'error': str(e)}
            conn.send(json.dumps(error_resp).encode() + b'\n')
        finally:
            conn.close()

    def _execute(self, request):
        """Execute code in IPython and return results."""
        code = request.get('code', '')
        capture = request.get('capture', True)

        stdout_capture = StringIO()
        stderr_capture = StringIO()

        if capture:
            old_stdout, old_stderr = sys.stdout, sys.stderr
            sys.stdout, sys.stderr = stdout_capture, stderr_capture

        try:
            # Use IPython's run_cell for proper namespace handling
            result = self.ipython.run_cell(code, silent=False)

            return {
                'status': 'error' if result.error_in_exec else 'ok',
                'result': repr(result.result) if result.result is not None else None,
                'stdout': stdout_capture.getvalue() if capture else '',
                'stderr': stderr_capture.getvalue() if capture else '',
                'error': str(result.error_in_exec) if result.error_in_exec else None,
            }
        except Exception as e:
            return {'status': 'error', 'error': str(e)}
        finally:
            if capture:
                sys.stdout, sys.stderr = old_stdout, old_stderr


def start_bridge(port=9999):
    """
    Start the bridge server.

    Parameters
    ----------
    port : int
        Port to listen on (default: 9999)

    Returns
    -------
    IPythonBridge
        The bridge instance (can be used to call stop())
    """
    global _bridge_instance
    import IPython
    ip = IPython.get_ipython()
    if ip is None:
        print("Error: Not in an IPython session")
        return None

    if _bridge_instance:
        _bridge_instance.stop()

    _bridge_instance = IPythonBridge(ip, port)
    _bridge_instance.start()
    return _bridge_instance


def stop_bridge():
    """Stop the bridge server."""
    global _bridge_instance
    if _bridge_instance:
        _bridge_instance.stop()
        _bridge_instance = None


# Auto-start when run as script
if __name__ == '__main__':
    start_bridge()
