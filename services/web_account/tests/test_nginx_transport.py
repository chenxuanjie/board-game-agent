"""Optional real Nginx integration, using only temporary files and a fake DSM.

NGINX_BIN=/path/to/nginx python -m unittest discover -s services/web_account/tests
No Docker build, live NAS credentials or product assets are used.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from urllib.parse import parse_qs

import httpx
import uvicorn

from services.web_account.app import Settings, create_app


def unused_port():
    with socket.socket() as stream:
        stream.bind(("127.0.0.1", 0))
        return stream.getsockname()[1]


@unittest.skipUnless(os.environ.get("NGINX_BIN"), "Set NGINX_BIN for local Nginx transport integration")
class NginxTransportTests(unittest.TestCase):
    def test_authenticated_range_revalidation_head_and_internal_boundary(self):
        binary = Path(os.environ["NGINX_BIN"]).resolve()
        repo = Path(__file__).resolve().parents[3]
        with tempfile.TemporaryDirectory(prefix="bga-nginx-") as temp:
            root = Path(temp)
            library = root / "library"
            game = library / "assets/games/sample"
            (game / "docs").mkdir(parents=True)
            (root / "logs").mkdir()
            (root / "temp").mkdir()
            (root / "web").mkdir()
            (root / "web/index.html").write_text("test shell")
            (library / "assets/catalog.json").write_text('{"games":[{"slug":"sample","enabled":true}]}')
            (game / "game.json").write_text('{}')
            (game / "manifest.json").write_text(json.dumps({"resources": [{"path": "docs/rules.pdf", "enabled": True, "status": "available"}]}))
            pdf = b"%PDF-" + bytes(range(256)) * 4096
            (game / "docs/rules.pdf").write_bytes(pdf)

            async def dsm(request):
                fields = {k: v[0] for k, v in parse_qs((await request.aread()).decode()).items()}
                if fields["api"] == "SYNO.API.Info":
                    data = {name: {"path": "entry.cgi", "minVersion": 1, "maxVersion": 7} for name in (
                        "SYNO.API.Auth", "SYNO.FileStation.Info", "SYNO.FileStation.Download")}
                elif fields["method"] == "login":
                    data = {"sid": "fake-private-sid"}
                elif fields["method"] == "get":
                    data = {"uid": 1001}
                elif fields["method"] == "download":
                    return httpx.Response(206, content=b"x", headers={"Content-Type": "application/octet-stream", "Content-Disposition": "attachment"})
                else:
                    data = {}
                return httpx.Response(200, json={"success": True, "data": data})

            web_port, api_port = unused_port(), unused_port()
            settings = Settings("https://nas.example:5001", "https://nas.example:5001", f"http://127.0.0.1:{web_port}",
                                insecure_http=True, library_root=str(library))
            upstream = httpx.AsyncClient(transport=httpx.MockTransport(dsm))
            app = create_app(settings, upstream)
            server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=api_port, log_level="error", loop="asyncio"))
            thread = threading.Thread(target=server.run, daemon=True)
            thread.start()
            nginx = None
            try:
                config = (repo / "packaging/docker/nginx.conf").read_text()
                config = config.replace("listen 80;", f"listen 127.0.0.1:{web_port};")
                config = config.replace("root /usr/share/nginx/html;", f'root "{(root / "web").as_posix()}";')
                config = config.replace("include /etc/nginx/mime.types;", f'include "{(binary.parent / "conf/mime.types").as_posix()}";')
                config = config.replace("http://web-account:8000", f"http://127.0.0.1:{api_port}")
                config = config.replace("alias /data/library/;", f'alias "{library.as_posix()}/";')
                if os.name == "nt":
                    # Windows Nginx has no openat/symlink-check implementation.
                    # The Python whitelist still validates each symlink; Linux
                    # Docker keeps disable_symlinks on in the real config.
                    config = config.replace("disable_symlinks on;", "")
                (root / "nginx.conf").write_text("worker_processes 1;\nerror_log logs/error.log;\npid logs/nginx.pid;\nevents {worker_connections 64;}\nhttp {\n" + config + "\n}")
                command = [str(binary), "-p", root.as_posix() + "/", "-c", "nginx.conf"]
                checked = subprocess.run(command + ["-t"], capture_output=True, text=True)
                self.assertEqual(checked.returncode, 0, checked.stderr)
                options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
                nginx = subprocess.Popen(command + ["-g", "daemon off;"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **options)
                with httpx.Client(base_url=settings.public_origin, trust_env=False, timeout=5,
                                  headers={"X-Board-Game-Request": "1"}) as client:
                    for _ in range(150):
                        try:
                            if server.started and client.get("/healthz").status_code == 200:
                                break
                        except httpx.TransportError:
                            pass
                        time.sleep(.02)
                    self.assertTrue(server.started)
                    uri = "/library/assets/games/sample/docs/rules.pdf"
                    self.assertEqual(client.get(uri).status_code, 401)
                    client.get("/api/account/session")
                    self.assertEqual(client.post("/api/account/login", json={"account": "test", "password": "test"}).status_code, 200)
                    partial = client.get(uri, headers={"Range": "bytes=100-199"})
                    self.assertEqual(partial.status_code, 206)
                    self.assertEqual(partial.content, pdf[100:200])
                    self.assertEqual(partial.headers["content-range"], f"bytes 100-199/{len(pdf)}")
                    self.assertEqual(partial.headers["cache-control"], "private, no-cache")
                    self.assertEqual(partial.headers["content-type"], "application/pdf")
                    self.assertNotIn("x-accel-redirect", partial.headers)
                    etag = partial.headers["etag"]
                    cached = client.get(uri, headers={"If-None-Match": etag})
                    self.assertEqual(cached.status_code, 304)
                    # Equal-size replacements within one second must not reuse
                    # the prior body merely because Nginx rounds mtime to seconds.
                    file = game / "docs/rules.pdf"
                    stat = file.stat()
                    changed = b"%PDF-new" + pdf[8:]
                    file.write_bytes(changed)
                    os.utime(file, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1000))
                    replacement = client.get(uri, headers={"If-None-Match": etag})
                    self.assertEqual(replacement.status_code, 200)
                    self.assertNotEqual(replacement.headers["etag"], etag)
                    self.assertEqual(replacement.content, changed)
                    head = client.head(uri)
                    self.assertEqual(head.status_code, 200)
                    self.assertEqual(int(head.headers["content-length"]), len(pdf))
                    self.assertEqual(client.get("/_library_files/assets/games/sample/docs/rules.pdf").status_code, 404)
                    self.assertEqual(client.get("/library/assets/missing.pdf").status_code, 404)
                    self.assertEqual(client.post("/api/account/logout").status_code, 200)
                    self.assertEqual(client.get(uri, headers={"If-None-Match": etag}).status_code, 401)
            finally:
                if nginx is not None:
                    subprocess.run(command + ["-s", "quit"], capture_output=True, **options)
                    try:
                        nginx.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        nginx.kill()
                        nginx.wait(timeout=5)
                server.should_exit = True
                thread.join(timeout=5)
