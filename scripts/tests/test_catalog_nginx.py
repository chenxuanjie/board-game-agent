"""Real Nginx transport with temporary files and a fake API, never NAS or image builds."""

import hashlib
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
class CatalogNginxTests(unittest.TestCase):
    def test_api_gated_file_range_validators_and_internal_boundary(self):
        docker = (
            ["wsl", "-d", "Ubuntu", "--exec", "docker"]
            if os.name == "nt"
            else ["docker"]
        )

        def run(*args):
            return subprocess.check_output(
                [*docker, *args], text=True, timeout=45
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
        prefix = "bga-files-test-" + uuid4().hex[:10]
        created = []
        temp_root = ROOT / ".local"
        temp_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=prefix + "-", dir=temp_root) as folder:
            root = Path(folder).resolve()
            self.assertTrue(root.is_relative_to(temp_root.resolve()))
            data = b"%PDF-fixture-" + bytes(range(256)) * 32
            digest = hashlib.sha256(data).hexdigest()
            blob = root / "library" / "blobs" / digest[:2] / digest
            blob.parent.mkdir(parents=True)
            blob.write_bytes(data)
            web = root / "web"
            web.mkdir()
            (web / "index.html").write_text("test shell")
            fixture = root / "fixture.py"
            fixture.write_text(
                '''import http.server,json
DATA=bytes.fromhex("'''
                + data.hex()
                + '''")
DIGEST="'''
                + digest
                + """"
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self): self.answer()
 def do_HEAD(self): self.answer()
 def log_message(self,*a): pass
 def answer(self):
  if self.path.startswith('/v1/apps/board_game_agent/catalog/resources/'):
   if '/withdrawn/' in self.path:
    self.send_response(404); self.end_headers(); return
   if self.headers.get('If-None-Match')=='"'+DIGEST+'"':
    self.send_response(304); self.send_header('ETag','"'+DIGEST+'"'); self.end_headers(); return
   self.send_response(200)
   self.send_header('Content-Type','application/pdf')
   self.send_header('ETag','"'+DIGEST+'"')
   self.send_header('Content-Disposition','inline; filename="rules.pdf"')
   self.send_header('Cache-Control','public, max-age=0, must-revalidate')
   if self.headers.get('X-BGA-File-Delivery')=='nginx':
    self.send_header('X-Accel-Redirect','/_catalog_files/'+DIGEST[:2]+'/'+DIGEST)
    self.send_header('Content-Length','0'); self.end_headers(); return
   self.send_header('Content-Length',str(len(DATA))); self.end_headers()
   if self.command!='HEAD': self.wfile.write(DATA)
   return
  self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
  if self.command!='HEAD': self.wfile.write(json.dumps({'path':self.path,'hint':self.headers.get('X-BGA-File-Delivery','')}).encode())
http.server.ThreadingHTTPServer(('0.0.0.0',8000),Handler).serve_forever()
"""
            )
            network = False
            try:
                run("network", "create", prefix)
                network = True
                fixture_name = prefix + "-api"
                run(
                    "run",
                    "-d",
                    "--name",
                    fixture_name,
                    "--network",
                    prefix,
                    "--network-alias",
                    "fixture",
                    "--mount",
                    "type=bind,src=" + linux(fixture) + ",dst=/fixture.py,readonly",
                    "python:3.14.2-slim-bookworm",
                    "python",
                    "/fixture.py",
                )
                created.append(fixture_name)
                nginx_name = prefix + "-web"
                run(
                    "run",
                    "-d",
                    "--name",
                    nginx_name,
                    "--network",
                    prefix,
                    "--read-only",
                    "--user",
                    "10001:10001",
                    "-e",
                    "APP_SERVICE_UPSTREAM=http://fixture:8000",
                    "-e",
                    "LIBRARY_ACCELERATION=1",
                    "--tmpfs",
                    "/tmp",
                    "-p",
                    "127.0.0.1::8080",
                    "--mount",
                    "type=bind,src="
                    + linux(ROOT / "packaging/docker/nginx-main.conf")
                    + ",dst=/etc/nginx/nginx.conf,readonly",
                    "--mount",
                    "type=bind,src="
                    + linux(ROOT / "packaging/docker/nginx.conf")
                    + ",dst=/opt/board-game-agent/nginx.conf.template,readonly",
                    "--mount",
                    "type=bind,src="
                    + linux(ROOT / "packaging/docker/start-web.sh")
                    + ",dst=/opt/board-game-agent/start-web.sh,readonly",
                    "--mount",
                    "type=bind,src="
                    + linux(root / "library")
                    + ",dst=/data/board-library,readonly",
                    "--mount",
                    "type=bind,src="
                    + linux(web)
                    + ",dst=/usr/share/nginx/html,readonly",
                    "--entrypoint",
                    "/bin/sh",
                    IMAGE,
                    "/opt/board-game-agent/start-web.sh",
                )
                created.append(nginx_name)
                port = run("port", nginx_name, "8080/tcp").rsplit(":", 1)[1]
                with httpx.Client(
                    base_url="http://127.0.0.1:" + port, trust_env=False, timeout=8
                ) as client:
                    for _ in range(100):
                        try:
                            if client.get("/healthz").status_code == 200:
                                break
                        except httpx.HTTPError:
                            pass
                        time.sleep(0.1)
                    uri = (
                        "/api/v1/apps/board_game_agent/catalog/resources/public/content"
                    )
                    response = client.get(uri)
                    self.assertEqual(response.status_code, 200)
                    self.assertEqual(response.content, data)
                    self.assertEqual(
                        response.headers["content-type"], "application/pdf"
                    )
                    self.assertEqual(
                        response.headers.get_list("etag"), ['"' + digest + '"']
                    )
                    self.assertIn("rules.pdf", response.headers["content-disposition"])
                    self.assertNotIn("x-accel-redirect", response.headers)
                    partial = client.get(
                        uri,
                        headers={"Range": "bytes=3-31", "If-Range": '"' + digest + '"'},
                    )
                    self.assertEqual(
                        (partial.status_code, partial.content), (206, data[3:32])
                    )
                    stale = client.get(
                        uri,
                        headers={"Range": "bytes=3-31", "If-Range": '"old-content"'},
                    )
                    self.assertEqual((stale.status_code, stale.content), (200, data))
                    self.assertEqual(
                        client.head(uri).headers["content-length"], str(len(data))
                    )
                    self.assertEqual(
                        client.get(
                            uri, headers={"If-None-Match": '"' + digest + '"'}
                        ).status_code,
                        304,
                    )
                    self.assertEqual(
                        client.get(
                            "/_catalog_files/" + digest[:2] + "/" + digest
                        ).status_code,
                        404,
                    )
                    self.assertEqual(
                        client.get("/_catalog_files/invalid").status_code, 404
                    )
                    self.assertEqual(
                        client.get(uri.replace("/public/", "/withdrawn/")).status_code,
                        404,
                    )
                    self.assertEqual(
                        client.get("/api/powersync/probe").json()["path"],
                        "/powersync/probe",
                    )
                    self.assertEqual(
                        client.get(
                            "/api/v1/probe", headers={"X-BGA-File-Delivery": "nginx"}
                        ).json()["hint"],
                        "",
                    )
            except Exception:
                for name in created:
                    print(run("logs", "--tail", "12", name))
                raise
            finally:
                for name in reversed(created):
                    run("rm", "-f", name)
                if network:
                    run("network", "rm", prefix)


if __name__ == "__main__":
    unittest.main()
