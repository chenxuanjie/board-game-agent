import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import parse_qs

import httpx

from services.web_account.app import create_app, Settings
from services.web_account.library import Library, LibraryError, logical_path


class LibraryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.library = Library(self.root)
        self.write("assets/catalog.json", {"games": [{"slug": "sample", "enabled": True}]})
        self.write("assets/games/sample/game.json", {"coverAsset": "images/cover.webp"})
        self.write("assets/games/sample/manifest.json", {"resources": [
            {"path": "docs/rules.pdf", "enabled": True, "status": "available"},
            {"path": "docs/hidden.pdf", "enabled": False},
            {"path": "docs/others/private.txt"},
            {"path": "../escape.txt"},
        ]})
        self.write("assets/games/sample/images/cover.webp", b"image")
        self.write("assets/games/sample/docs/rules.pdf", b"%PDF-test")
        self.write("assets/games/sample/docs/hidden.pdf", b"hidden")

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value if isinstance(value, bytes) else json.dumps(value).encode())

    def test_only_enabled_published_resources_are_resolved(self):
        for path in ("assets/catalog.json", "assets/games/sample/images/cover.webp", "assets/games/sample/docs/rules.pdf"):
            self.assertTrue(self.library.resolve(path).is_file())
        for path in ("assets/games/sample/docs/hidden.pdf", "assets/games/sample/docs/others/private.txt", "assets/unpublished.txt"):
            with self.assertRaises(LibraryError):
                self.library.resolve(path)

    def test_traversal_and_encoded_paths_rejected(self):
        for value in ("/etc/passwd", "assets/../secret", "assets/%2e%2e/secret", "assets/.env", "assets//file", "assets/evil\\file", "assets/file?query", "assets/file\n", "assets/games/x/docs/others/secret"):
            with self.subTest(path=value), self.assertRaises(LibraryError):
                logical_path(value)

    def test_manifest_changes_revoke_old_paths_and_catalog_removes_game(self):
        self.library.resolve("assets/games/sample/docs/rules.pdf")
        self.write("assets/games/sample/manifest.json", {"resources": []})
        with self.assertRaises(LibraryError):
            self.library.resolve("assets/games/sample/docs/rules.pdf")
        self.write("assets/catalog.json", {"games": [{"slug": "sample", "enabled": False}]})
        self.assertEqual(self.library.paths(), {"assets/catalog.json"})

    def test_versions_detect_replacement_and_missing_file(self):
        path = "assets/games/sample/docs/rules.pdf"
        before = {v["path"]: v for v in self.library.versions()}[path]
        self.write(path, b"%PDF-a-longer-replacement")
        after = {v["path"]: v for v in self.library.versions()}[path]
        self.assertNotEqual(before["version"], after["version"])
        (self.root / path).unlink()
        self.assertFalse({v["path"]: v for v in self.library.versions()}[path]["exists"])

    def test_listing_is_bounded_and_excludes_disabled(self):
        entries = self.library.entries("assets/games/sample/docs", 6, 1)
        self.assertEqual([v["name"] for v in entries], ["rules.pdf"])
        self.assertEqual(len(self.library.entries("assets", 10, 2)), 2)

    def test_empty_or_invalid_image_does_not_hide_valid_documents(self):
        self.write("assets/games/sample/game.json", {"coverAsset": "", "bannerAsset": "../invalid", "galleryAssets": None})
        self.assertTrue(self.library.resolve("assets/games/sample/docs/rules.pdf").is_file())

    def test_symlink_is_never_served(self):
        file = self.root / "assets/games/sample/docs/rules.pdf"
        file.unlink()
        try:
            file.symlink_to(self.root / "assets/catalog.json")
        except OSError:
            self.skipTest("Host does not permit symlinks")
        with self.assertRaises(LibraryError):
            self.library.resolve("assets/games/sample/docs/rules.pdf")

    def test_invalid_catalog_and_oversized_json_fail_closed(self):
        self.write("assets/catalog.json", {"games": [{"slug": "../escape"}]})
        with self.assertRaises(LibraryError):
            self.library.paths()
        self.write("assets/catalog.json", b" " * (4 * 1024 * 1024 + 1))
        with self.assertRaises(LibraryError):
            self.library.paths()


class LibraryGatewayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        (root / "assets").mkdir()
        (root / "assets/catalog.json").write_text('{"games":[]}', encoding="utf-8")
        self.fields = []
        self.download_error = None
        self.download_gate = None
        self.settings = Settings("https://nas.example:5001", "https://nas.example:5001", "https://games.example", library_root=str(root))
        self.upstream = httpx.AsyncClient(transport=httpx.MockTransport(self.dsm))
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=create_app(self.settings, self.upstream), raise_app_exceptions=False),
                                      base_url="https://games.example", headers={"X-Board-Game-Request": "1"})

    async def asyncTearDown(self):
        await self.client.aclose()
        await self.upstream.aclose()
        self.temp.cleanup()

    async def dsm(self, request):
        self.assertEqual(request.method, "POST")
        self.assertEqual(request.url.query, b"")
        self.assertEqual(request.headers.get("cookie", ""), "")
        fields = {k: v[0] for k, v in parse_qs((await request.aread()).decode()).items()}
        self.fields.append(fields)
        if fields["api"] == "SYNO.API.Info":
            return httpx.Response(200, json={"success": True, "data": {
                name: {"path": "entry.cgi", "minVersion": 1, "maxVersion": 7}
                for name in ("SYNO.API.Auth", "SYNO.FileStation.Info", "SYNO.FileStation.Download")}})
        if fields["method"] == "login":
            data = {"sid": "private-sid"}
        elif fields["method"] == "get":
            data = {"uid": 1001}
        elif fields["method"] == "download":
            self.assertEqual(request.headers["range"], "bytes=0-0")
            self.assertEqual(json.loads(fields["path"]), [self.settings.library_nas_path + "/assets/catalog.json"])
            if self.download_gate:
                await self.download_gate.wait()
            if self.download_error:
                return httpx.Response(200, json={"success": False, "error": {"code": self.download_error}})
            return httpx.Response(206, content=b"{", headers={"Content-Type": "application/json", "Content-Disposition": "attachment"})
        else:
            data = {}
        return httpx.Response(200, json={"success": True, "data": data})

    async def login(self):
        await self.client.get("/api/account/session")
        self.assertEqual((await self.client.post("/api/account/login", json={"account": "Shane", "password": "test"})).status_code, 200)

    async def test_anonymous_cannot_access_files_or_versions(self):
        for path in ("/library/assets/catalog.json", "/api/library/versions", "/api/library/files"):
            self.assertEqual((await self.client.get(path)).status_code, 401)
        self.assertEqual(self.fields, [])

    async def test_file_uses_internal_redirect_after_exact_read_proof(self):
        await self.login()
        for method in ("GET", "HEAD"):
            response = await self.client.request(method, "/library/assets/catalog.json")
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.headers["x-accel-redirect"], "/_library_files/assets/catalog.json")
            self.assertEqual(response.content, b"")
            self.assertNotIn("private-sid", str(response.headers))
        self.assertEqual(len([f for f in self.fields if f.get("query") == "SYNO.FileStation.Download"]), 1)

    async def test_rejected_permission_and_expired_sid_never_redirect(self):
        await self.login()
        for code, status in ((407, 403), (119, 401)):
            self.download_error = code
            response = await self.client.get("/library/assets/catalog.json")
            self.assertEqual(response.status_code, status)
            self.assertNotIn("x-accel-redirect", response.headers)

    async def test_logout_during_permission_probe_rejects_late_file(self):
        await self.login()
        self.download_gate = asyncio.Event()
        pending = asyncio.create_task(self.client.get("/library/assets/catalog.json"))
        for _ in range(100):
            if any(f.get("method") == "download" for f in self.fields):
                break
            await asyncio.sleep(.001)
        self.assertEqual((await self.client.post("/api/account/logout")).status_code, 200)
        self.download_gate.set()
        self.assertEqual((await pending).status_code, 401)

    async def test_cross_origin_and_unregistered_paths_are_rejected(self):
        await self.login()
        self.assertEqual((await self.client.get("/library/assets/catalog.json", headers={"Origin": "https://evil.example"})).status_code, 403)
        self.assertEqual((await self.client.get("/library/assets/hidden.txt")).status_code, 404)
        self.assertFalse(any(f.get("method") == "download" for f in self.fields))

    async def test_versions_and_listing_use_published_local_metadata(self):
        await self.login()
        version = await self.client.get("/api/library/versions")
        self.assertEqual(version.status_code, 200)
        self.assertTrue(version.json()["files"][0]["exists"])
        listing = await self.client.get("/api/library/files?path=assets&limit=1")
        self.assertEqual(listing.json()["files"][0]["path"], "assets/catalog.json")


if __name__ == "__main__":
    unittest.main()
