import asyncio
import importlib.util
import socket
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import httpx
import uvicorn
from starlette.testclient import TestClient

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "web_preview", ROOT / "scripts/web_preview_server.py"
)
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)
SITE = "https://localhost:8084"


class Bytes(httpx.AsyncByteStream):
    def __init__(self, data):
        self.data = data
        self.closed = False

    async def __aiter__(self):
        yield self.data

    async def aclose(self):
        self.closed = True


class PreviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "index.html").write_text("preview shell")
        (self.root / "main.dart.js").write_text("code")
        self.requests = []

    def app(self, handler, **kwargs):
        async def record(request):
            self.requests.append(request)
            return await handler(request)

        client = httpx.AsyncClient(transport=httpx.MockTransport(record))
        return preview.create_app(
            self.root,
            "https://api.example.test",
            origins=[SITE],
            api_client=client,
            **kwargs,
        )

    def test_api_prefix_cookies_csrf_and_multiple_set_cookie_are_preserved(self):
        async def upstream(request):
            return httpx.Response(
                200,
                headers=[
                    (
                        "Set-Cookie",
                        "__Host-app-session-board_game_agent=fixture; Secure; HttpOnly; Path=/",
                    ),
                    ("Set-Cookie", "second=fixture; Secure; Path=/"),
                    ("Content-Type", "application/json"),
                ],
                stream=Bytes(b'{"ok":true}'),
            )

        with TestClient(self.app(upstream), base_url=SITE) as client:
            response = client.post(
                "/api/v1/apps/board_game_agent/auth/browser/restore?probe=1",
                json={},
                headers={
                    "Origin": SITE,
                    "Cookie": "fixture=1",
                    "X-CSRF-Token": "csrf-fixture",
                    "X-BGA-File-Delivery": "nginx",
                    "X-Release-Publish-Key": "must-not-forward",
                },
            )
            self.assertEqual(response.json(), {"ok": True})
            self.assertEqual(len(response.headers.get_list("set-cookie")), 2)
            request = self.requests[0]
            self.assertEqual(
                str(request.url),
                "https://api.example.test/v1/apps/board_game_agent/auth/browser/restore?probe=1",
            )
            for name, value in [
                ("cookie", "fixture=1"),
                ("x-csrf-token", "csrf-fixture"),
                ("origin", SITE),
            ]:
                self.assertEqual(request.headers[name], value)
            self.assertNotIn("x-bga-file-delivery", request.headers)
            self.assertNotIn("x-release-publish-key", request.headers)
            self.assertEqual(
                response.headers["cross-origin-embedder-policy"], "require-corp"
            )

    def test_pdf_range_head_and_sync_path_are_forwarded_without_body_buffering(self):
        async def upstream(request):
            if request.url.path.startswith("/powersync/"):
                return httpx.Response(200, stream=Bytes(b'{"checkpoint_complete":1}\n'))
            headers = {
                "ETag": '"digest"',
                "Content-Type": "application/pdf",
                "Content-Length": "4",
            }
            if request.headers.get("range"):
                headers["Content-Range"] = "bytes 0-3/10"
            return httpx.Response(
                206 if "range" in request.headers else 200,
                headers=headers,
                stream=Bytes(b"" if request.method == "HEAD" else b"%PDF"),
            )

        with TestClient(self.app(upstream), base_url=SITE) as client:
            response = client.get(
                "/api/v1/apps/board_game_agent/catalog/resources/r/content",
                headers={"Range": "bytes=0-3"},
            )
            self.assertEqual((response.status_code, response.content), (206, b"%PDF"))
            self.assertEqual(response.headers["content-range"], "bytes 0-3/10")
            self.assertEqual(client.head("/api/v1/pdf").headers["content-length"], "4")
            self.assertEqual(
                client.post("/api/powersync/sync/stream", json={}).status_code, 200
            )

    def test_cross_site_and_unknown_proxy_paths_do_not_reach_api(self):
        async def upstream(_):
            self.fail("must not reach upstream")

        with TestClient(self.app(upstream), base_url=SITE) as client:
            self.assertEqual(
                client.post(
                    "/api/v1/auth", json={}, headers={"Origin": "https://evil.test"}
                ).status_code,
                403,
            )
            self.assertEqual(client.get("/api/elsewhere").status_code, 404)
            self.assertEqual(
                client.get(
                    "/api/v1/a", headers={"Sec-Fetch-Site": "cross-site"}
                ).status_code,
                403,
            )
            with patch.object(preview, "LIMIT", 3):
                self.assertEqual(
                    client.post("/api/v1/a", content=b"1234").status_code, 413
                )

    def test_static_spa_missing_asset_and_same_size_change_revalidation(self):
        async def upstream(_):
            self.fail("static request reached API")

        with TestClient(self.app(upstream), base_url=SITE) as client:
            self.assertEqual(client.get("/settings/account").text, "preview shell")
            self.assertEqual(client.get("/missing.js").status_code, 404)
            before = client.get("/main.dart.js")
            self.assertEqual(
                client.get(
                    "/main.dart.js", headers={"If-None-Match": before.headers["etag"]}
                ).status_code,
                304,
            )
            (self.root / "main.dart.js").write_text("edit")
            self.assertEqual(
                client.get(
                    "/main.dart.js", headers={"If-None-Match": before.headers["etag"]}
                ).status_code,
                200,
            )

    def test_byok_uses_existing_allowlist_and_does_not_forward_browser_cookies(self):
        async def upstream(_):
            self.fail("BYOK reached application API")

        async def provider(request):
            self.assertEqual(request.headers.get("cookie", ""), "")
            self.assertNotIn("x-csrf-token", request.headers)
            self.assertEqual(request.headers["authorization"], "Bearer fixture-key")
            return httpx.Response(
                200,
                headers={"content-type": "application/json"},
                stream=Bytes(b'{"data":[]}'),
            )

        ai = httpx.AsyncClient(transport=httpx.MockTransport(provider))
        with TestClient(self.app(upstream, ai_client=ai), base_url=SITE) as client:
            headers = {
                "Origin": SITE,
                "X-Board-Game-Request": "1",
                "X-BGA-AI-Target": "https://www.loomex.lol/v1/models",
                "Authorization": "Bearer fixture-key",
                "Cookie": "private=fixture",
                "X-CSRF-Token": "private-fixture",
            }
            self.assertEqual(
                client.get("/api/ai/request", headers=headers).json(), {"data": []}
            )
            headers["X-BGA-AI-Target"] = "https://127.0.0.1/v1/models"
            self.assertEqual(
                client.get("/api/ai/request", headers=headers).status_code, 403
            )

    def test_sse_first_chunk_arrives_before_completion_and_disconnect_closes_upstream(
        self,
    ):
        release = threading.Event()
        closed = threading.Event()

        class Stream(httpx.AsyncByteStream):
            async def __aiter__(self):
                yield b"data: first\n\n"
                for _ in range(500):
                    if release.is_set():
                        break
                    await asyncio.sleep(0.01)
                yield b"data: final\n\n"

            async def aclose(self):
                closed.set()

        async def upstream(_):
            return httpx.Response(
                200, headers={"Content-Type": "text/event-stream"}, stream=Stream()
            )

        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        server = uvicorn.Server(
            uvicorn.Config(
                self.app(upstream),
                host="127.0.0.1",
                port=port,
                access_log=False,
                log_level="error",
            )
        )
        thread = threading.Thread(target=server.run, daemon=True)
        thread.start()
        try:
            for _ in range(100):
                if server.started:
                    break
                time.sleep(0.02)
            self.assertTrue(server.started)
            with httpx.stream(
                "GET", f"http://127.0.0.1:{port}/api/v1/stream", timeout=3
            ) as response:
                self.assertEqual(next(response.iter_lines()), "data: first")
                self.assertFalse(release.is_set())
            self.assertTrue(closed.wait(3))
        finally:
            release.set()
            server.should_exit = True
            thread.join(5)


if __name__ == "__main__":
    unittest.main()
