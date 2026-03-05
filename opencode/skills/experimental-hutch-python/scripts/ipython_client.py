"""
Client for sending commands to IPython via the bridge.

Usage:
    from ipython_client import IPythonClient

    client = IPythonClient('localhost', 9999)
    result = client.execute('1 + 1')
    print(result)
    # {'status': 'ok', 'result': '2', 'stdout': '', 'stderr': '', 'error': None}
"""
import json
import socket


class IPythonClient:
    """
    Client for communicating with an IPython session via the bridge.

    Parameters
    ----------
    host : str
        Hostname to connect to (default: 'localhost')
    port : int
        Port number (default: 9999)
    timeout : float
        Socket timeout in seconds (default: 60)
    """

    def __init__(self, host='localhost', port=9999, timeout=60):
        self.host = host
        self.port = port
        self.timeout = timeout

    def execute(self, code, capture=True):
        """
        Send code to IPython for execution and return the result.

        Parameters
        ----------
        code : str
            Python code to execute
        capture : bool
            Whether to capture stdout/stderr (default: True)

        Returns
        -------
        dict
            Response containing:
            - status: 'ok' or 'error'
            - result: repr of return value (or None)
            - stdout: captured stdout
            - stderr: captured stderr
            - error: error message if status is 'error'
        """
        request = {'code': code, 'capture': capture}

        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)

        try:
            sock.connect((self.host, self.port))
            sock.send(json.dumps(request).encode() + b'\n')

            response = b''
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response += chunk
                if b'\n' in response:
                    break

            return json.loads(response.decode())
        except socket.timeout:
            return {'status': 'error', 'error': f'Timeout after {self.timeout}s'}
        except ConnectionRefusedError:
            return {'status': 'error', 'error': 'Connection refused - is the bridge running?'}
        except Exception as e:
            return {'status': 'error', 'error': str(e)}
        finally:
            sock.close()

    def is_alive(self):
        """
        Check if the bridge is responding.

        Returns
        -------
        bool
            True if bridge responds successfully
        """
        try:
            result = self.execute('True', capture=False)
            return result.get('status') == 'ok'
        except Exception:
            return False


# Quick test when run directly
if __name__ == '__main__':
    client = IPythonClient()
    print("Testing connection to IPython bridge...")
    result = client.execute('1 + 1')
    print(f"Result: {result}")
