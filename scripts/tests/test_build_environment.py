"""Real loopback forwarding and diagnostic failure tests; no external services."""
import json
from pathlib import Path
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_diagnostics import TaskLog


class BuildEnvironmentTests(unittest.TestCase):
    def test_capture_keeps_stdout_for_callers_and_on_disk(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = TaskLog(temporary, 'capture-test')
            result = log.run('python-version', [sys.executable, '--version'], capture=True, timeout=10)
            self.assertIn('Python', result.stdout)
            record = log.stages[0]
            self.assertEqual(record['status'], 'passed')
            self.assertEqual((log.directory / record['log']).read_text().strip(), result.stdout.strip())

    def test_failed_and_timed_out_stages_keep_complete_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = TaskLog(temporary, 'fault-test')
            for name, code, deadline, exception in (
                ('failure', "print('failure evidence', flush=True); raise SystemExit(7)", 5, subprocess.CalledProcessError),
                ('timeout', "import time; print('before timeout', flush=True); time.sleep(5)", .2, subprocess.TimeoutExpired),
            ):
                with self.assertRaises(exception):
                    log.run(name, [sys.executable, '-u', '-c', code], timeout=deadline)
            report = json.loads((log.directory / 'stages.json').read_text())
            self.assertEqual(report['stages'][0]['exitCode'], 7)
            self.assertEqual(report['stages'][1]['errorType'], 'TimeoutExpired')
            self.assertIn('failure evidence', (log.directory / '01-failure.log').read_text())
            self.assertIn('before timeout', (log.directory / '02-timeout.log').read_text())

    def test_forward_preserves_binary_data_and_half_close(self):
        class Echo(socketserver.BaseRequestHandler):
            def handle(self):
                self.request.settimeout(3)
                data = bytearray()
                while chunk := self.request.recv(65536):
                    data.extend(chunk)
                self.request.sendall(bytes(data))

        with socketserver.ThreadingTCPServer(('127.0.0.1', 0), Echo) as upstream:
            worker = threading.Thread(target=upstream.serve_forever, daemon=True)
            worker.start()
            with socket.socket() as candidate:
                candidate.bind(('127.0.0.1', 0))
                port = candidate.getsockname()[1]
            process = subprocess.Popen([
                sys.executable, str(ROOT / 'scripts/local-docker-proxy.py'), 'forward',
                '--listen-port', str(port), '--proxy-port', str(upstream.server_address[1]),
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                deadline = time.monotonic() + 5
                while True:
                    try:
                        client = socket.create_connection(('127.0.0.1', port), timeout=.2)
                        break
                    except OSError:
                        if time.monotonic() >= deadline:
                            raise
                        time.sleep(.02)
                with client:
                    client.settimeout(3)
                    payload = bytes(range(256)) * 1024
                    client.sendall(payload)
                    client.shutdown(socket.SHUT_WR)
                    received = bytearray()
                    while chunk := client.recv(65536):
                        received.extend(chunk)
                    self.assertEqual(bytes(received), payload)
            finally:
                process.terminate()
                process.wait(timeout=5)
                upstream.shutdown()
                worker.join(timeout=2)


if __name__ == '__main__':
    unittest.main()
