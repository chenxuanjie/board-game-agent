"""Real Nginx startup and forwarding policy, using existing local images only."""

import json
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from uuid import uuid4

import httpx

ROOT = Path(__file__).resolve().parents[2]
IMAGE = os.environ.get("BGA_NGINX_TEST_IMAGE")


@unittest.skipUnless(IMAGE, "Select an existing Nginx image with BGA_NGINX_TEST_IMAGE")
class TrustedProxyNginxTests(unittest.TestCase):
    def test_real_ingress_ignores_untrusted_headers_and_overwrites_verified_chain(self):
        docker = (
            ["wsl", "-d", "Ubuntu", "--exec", "docker"]
            if os.name == "nt"
            else ["docker"]
        )

        def run(*args):
            return subprocess.check_output(
                [*docker, *args], text=True, stderr=subprocess.STDOUT, timeout=45
            ).strip()

        def linux(path):
            if os.name == "nt":
                return subprocess.check_output(
                    ["wsl", "-d", "Ubuntu", "--exec", "wslpath", "-a", str(path)],
                    text=True,
                    timeout=10,
                ).strip()
            return str(path)

        run("image", "inspect", IMAGE)
        run("image", "inspect", "python:3.14.2-slim-bookworm")
        prefix = "bga-proxy-test-" + uuid4().hex[:10]
        created = []
        with tempfile.TemporaryDirectory(
            prefix=prefix, dir=ROOT / ".local"
        ) as directory:
            root = Path(directory)
            etags = root / "web-etags.map"
            etags.write_text("", encoding="utf-8")
            fixture = root / "echo.py"
            fixture.write_text(
                """from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
class Echo(BaseHTTPRequestHandler):
 def log_message(self,*a): pass
 def do_GET(self):
  data=json.dumps(dict(self.headers)).encode()
  self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
ThreadingHTTPServer(('0.0.0.0',8000),Echo).serve_forever()
""",
                encoding="utf-8",
            )
            run("network", "create", prefix)
            try:
                network = json.loads(run("network", "inspect", prefix))[0]
                gateway = network["IPAM"]["Config"][0]["Gateway"]
                api = prefix + "-api"
                run(
                    "run",
                    "-d",
                    "--pull",
                    "never",
                    "--name",
                    api,
                    "--network",
                    prefix,
                    "--network-alias",
                    "fixture",
                    "--user",
                    "65532:65532",
                    "--mount",
                    f"type=bind,src={linux(fixture)},dst=/echo.py,readonly",
                    "--entrypoint",
                    "python",
                    "python:3.14.2-slim-bookworm",
                    "/echo.py",
                )
                created.append(api)
                for mode in ("untrusted", "trusted", "reject-all"):
                    name = prefix + "-" + mode
                    trust = (
                        gateway
                        if mode == "trusted"
                        else "0.0.0.0/0"
                        if mode == "reject-all"
                        else ""
                    )
                    args = [
                        "run",
                        "-d",
                        "--pull",
                        "never",
                        "--name",
                        name,
                        "--network",
                        prefix,
                        "--read-only",
                        "--tmpfs",
                        "/tmp",
                        "--cap-drop",
                        "ALL",
                        "-p",
                        "127.0.0.1::8080",
                        "-e",
                        "APP_SERVICE_UPSTREAM=http://fixture:8000",
                        "-e",
                        "BGA_TRUSTED_PROXIES=" + trust,
                    ]
                    args.extend(
                        [
                            "--mount",
                            f"type=bind,src={linux(etags)},dst=/opt/board-game-agent/web-etags.map,readonly",
                        ]
                    )
                    for source, destination in (
                        ("packaging/docker/nginx-main.conf", "/etc/nginx/nginx.conf"),
                        (
                            "packaging/docker/nginx.conf",
                            "/opt/board-game-agent/nginx.conf.template",
                        ),
                        (
                            "packaging/docker/start-web.sh",
                            "/opt/board-game-agent/start-web.sh",
                        ),
                    ):
                        args.extend(
                            [
                                "--mount",
                                f"type=bind,src={linux(ROOT / source)},dst={destination},readonly",
                            ]
                        )
                    args.extend(
                        [
                            "--entrypoint",
                            "/bin/sh",
                            IMAGE,
                            "/opt/board-game-agent/start-web.sh",
                        ]
                    )
                    run(*args)
                    created.append(name)
                    if mode == "reject-all":
                        self.assertEqual(run("wait", name), "1")
                        self.assertIn("Trust specific proxies", run("logs", name))
                        continue
                    port = run("port", name, "8080/tcp").rsplit(":", 1)[1]
                    with httpx.Client(
                        base_url="http://127.0.0.1:" + port, trust_env=False, timeout=3
                    ) as client:
                        for _ in range(80):
                            try:
                                if client.get("/healthz").status_code == 200:
                                    break
                            except httpx.HTTPError:
                                pass
                            time.sleep(0.1)
                        spoof = {
                            "X-Forwarded-For": "203.0.113.99, 198.51.100.23",
                            "Forwarded": "for=203.0.113.99",
                            "X-Forwarded-Proto": "https",
                            "X-Forwarded-Host": "attacker.invalid",
                        }
                        result = client.get("/api/v1/test", headers=spoof)
                        self.assertEqual(result.status_code, 200, result.text)
                        headers = {k.lower(): v for k, v in result.json().items()}
                        expected = "198.51.100.23" if mode == "trusted" else gateway
                        self.assertEqual(headers["x-forwarded-for"], expected)
                        self.assertEqual(headers["x-real-ip"], expected)
                        for header in (
                            "forwarded",
                            "x-forwarded-proto",
                            "x-forwarded-host",
                        ):
                            self.assertNotIn(header, headers)
            except Exception:
                for name in created:
                    print(run("logs", "--tail", "12", name))
                raise
            finally:
                for name in reversed(created):
                    run("rm", "-f", name)
                run("network", "rm", prefix)


if __name__ == "__main__":
    unittest.main()
