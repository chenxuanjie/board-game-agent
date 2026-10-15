import asyncio
import hashlib
import json
import unittest
from urllib.parse import parse_qs

import httpx

from services.web_account.app import Settings, create_app


class AccountTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.events = []
        self.login_error = None
        self.info_error = None
        self.info_uid = 1001
        self.auth_status = 200
        self.malformed = False
        self.login_gate = None
        self.info_gate = None
        self.logout_fails = False
        self.paths_bad = False
        self.settings = Settings("https://nas.example:5001", "https://canonical.example:5001", "https://games.example")
        self.upstream = httpx.AsyncClient(transport=httpx.MockTransport(self.dsm))
        self.app = create_app(self.settings, self.upstream)
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app, raise_app_exceptions=False),
                                        base_url="https://games.example",
                                        headers={"X-Board-Game-Request": "1", "Origin": "https://games.example"})

    async def asyncTearDown(self):
        await self.client.aclose()
        await self.upstream.aclose()

    async def dsm(self, request):
        self.assertEqual(request.method, "POST")
        self.assertEqual(request.url.query, b"")
        self.assertEqual(request.url.host, "nas.example")
        self.assertEqual(request.headers.get("cookie", ""), "")
        fields = {key: values[0] for key, values in parse_qs((await request.aread()).decode()).items()}
        self.events.append(fields)
        if self.auth_status != 200:
            return httpx.Response(self.auth_status)
        if self.malformed:
            return httpx.Response(200, content=b"<html>gateway unavailable</html>")
        api, method = fields["api"], fields["method"]
        if api == "SYNO.API.Info":
            return httpx.Response(200, json={"success": True, "data": {
                "SYNO.API.Auth": {"path": "../escape.cgi" if self.paths_bad else "auth.cgi", "minVersion": 1, "maxVersion": 7},
                "SYNO.FileStation.Info": {"path": "entry.cgi", "minVersion": 1, "maxVersion": 2}}})
        if method == "login":
            if self.login_gate:
                await self.login_gate.wait()
            if self.login_error:
                return httpx.Response(200, json={"success": False, "error": {"code": self.login_error}})
            return httpx.Response(200, json={"success": True, "data": {"sid": "secret-sid", "synotoken": "secret-token"}})
        if method == "logout":
            if self.logout_fails:
                raise httpx.ConnectError("offline")
            return httpx.Response(200, json={"success": True})
        if self.info_gate:
            await self.info_gate.wait()
        if self.info_error:
            return httpx.Response(200, json={"success": False, "error": {"code": self.info_error}})
        return httpx.Response(200, json={"success": True, "data": {"uid": self.info_uid}})

    async def login(self, **kwargs):
        await self.client.get("/api/account/session")
        return await self.client.post("/api/account/login", json={"account": "Shane", "password": "transient-password", **kwargs})

    async def test_verified_login_and_cookie_only_restore(self):
        initial = await self.client.get("/api/account/session")
        self.assertEqual(initial.json(), {"user": None})
        cookie = initial.headers["set-cookie"]
        for attribute in ("HttpOnly", "Secure", "SameSite=strict", "Path=/"):
            self.assertIn(attribute, cookie)
        result = await self.login()
        expected = hashlib.sha256(b"synology-direct-v1|https://canonical.example:5001|1001").hexdigest()
        self.assertEqual(result.json()["user"]["id"], expected)
        self.assertEqual(result.json()["user"]["displayName"], "Shane")
        self.assertNotIn("set-cookie", result.headers)
        self.assertEqual((await self.client.get("/api/account/session")).json(), result.json())
        for secret in ("secret-sid", "secret-token", "transient-password"):
            self.assertNotIn(secret, result.text + cookie)
        self.assertEqual(result.headers["cache-control"], "no-store")

    async def test_config_uses_only_deployment_origins(self):
        value = (await self.client.get("/api/account/config")).json()
        self.assertEqual(value, {"version": 1, "nasOrigin": self.settings.nas_origin, "identityOrigin": self.settings.identity_origin})

    async def test_otp_failure_mapping_and_retry(self):
        for code, name in ((400, "invalidCredentials"), (403, "otpRequired"), (404, "invalidOtp"),
                           (407, "rateLimited"), (408, "passwordChangeRequired")):
            self.login_error = code
            self.assertEqual((await self.login()).json()["error"], name)
            self.assertIsNone((await self.client.get("/api/account/session")).json()["user"])
        self.login_error = None
        self.assertEqual((await self.login(otp="123456")).status_code, 200)
        self.assertEqual(self.events[-2]["otp_code"], "123456")

    async def test_unverified_sid_is_never_a_login(self):
        self.info_error = 105
        self.assertEqual((await self.login()).json()["error"], "accountDenied")
        self.assertEqual(self.events[-1]["method"], "logout")
        self.assertIsNone((await self.client.get("/api/account/session")).json()["user"])

    async def test_session_expiry_and_uid_change_invalidate_identity(self):
        for error, uid in ((106, 1001), (None, 1002)):
            self.info_error, self.info_uid = None, 1001
            self.assertEqual((await self.login()).status_code, 200)
            self.info_error, self.info_uid = error, uid
            self.assertIsNone((await self.client.get("/api/account/session")).json()["user"])

    async def test_logout_clears_local_session_even_when_nas_is_offline(self):
        await self.login()
        self.logout_fails = True
        self.assertEqual((await self.client.post("/api/account/logout", json={})).status_code, 200)
        self.assertIsNone((await self.client.get("/api/account/session")).json()["user"])

    async def test_cancelled_login_cannot_reappear_after_logout(self):
        await self.client.get("/api/account/session")
        self.login_gate = asyncio.Event()
        task = asyncio.create_task(self.client.post("/api/account/login", json={"account": "Shane", "password": "test"}))
        for _ in range(100):
            if any(event["method"] == "login" for event in self.events):
                break
            await asyncio.sleep(0)
        self.assertEqual((await self.client.post("/api/account/logout", json={})).status_code, 200)
        self.login_gate.set()
        self.assertEqual((await task).json()["error"], "cancelled")
        self.assertEqual(self.events[-1]["method"], "logout")
        self.assertIsNone((await self.client.get("/api/account/session")).json()["user"])

    async def test_verification_cannot_publish_after_logout(self):
        await self.login()
        self.info_gate = asyncio.Event()
        task = asyncio.create_task(self.client.get("/api/account/session"))
        await asyncio.sleep(0.01)
        await self.client.post("/api/account/logout", json={})
        self.info_gate.set()
        self.assertIsNone((await task).json()["user"])

    async def test_cross_origin_and_missing_header_are_rejected(self):
        for headers in ({"Origin": "https://evil.example"}, {"X-Board-Game-Request": ""}, {"Sec-Fetch-Site": "cross-site"}):
            self.assertEqual((await self.client.get("/api/account/session", headers=headers)).status_code, 403)
        self.assertEqual((await self.client.options("/api/account/login", headers={"Origin": "https://evil.example"})).status_code, 405)
        self.assertEqual(self.events, [])

    async def test_arbitrary_proxy_fields_and_oversize_body_are_rejected(self):
        await self.client.get("/api/account/session")
        for body in ({"account": "Shane", "password": "test", "origin": "https://evil.example"},
                     {"account": "Shane", "password": "test", "otp": "bad"},
                     {"account": "Shane", "password": "x" * 9000}):
            self.assertEqual((await self.client.post("/api/account/login", json=body)).status_code, 400)
        self.assertEqual(self.events, [])

    async def test_login_requires_anonymous_session(self):
        result = await self.client.post("/api/account/login", json={"account": "Shane", "password": "test"})
        self.assertEqual(result.status_code, 401)
        self.assertEqual(self.events, [])

    async def test_rate_limit_bounds_repeated_credentials(self):
        self.login_error = 400
        for _ in range(10):
            await self.login()
        self.assertEqual((await self.login()).status_code, 429)
        self.assertEqual(sum(e["method"] == "login" for e in self.events), 10)

    async def test_upstream_429_503_and_invalid_json_are_sanitized(self):
        for status, error in ((429, "rateLimited"), (503, "providerUnavailable")):
            self.auth_status = status
            self.assertEqual((await self.login()).json(), {"error": error})
        self.auth_status, self.malformed = 200, True
        self.assertEqual((await self.login()).json(), {"error": "providerUnavailable"})

    async def test_discovery_paths_cannot_escape_fixed_upstream(self):
        self.paths_bad = True
        self.assertEqual((await self.login()).json()["error"], "providerUnavailable")
        self.assertEqual(len(self.events), 1)

    async def test_bad_uid_types_are_rejected(self):
        self.info_uid = True
        self.assertEqual((await self.login()).json()["error"], "sessionRejected")

    async def test_server_restart_invalidates_browser_cookie(self):
        await self.login()
        fresh = create_app(self.settings, self.upstream)
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=fresh), base_url="https://games.example",
                                    headers=self.client.headers, cookies=self.client.cookies) as browser:
            self.assertIsNone((await browser.get("/api/account/session")).json()["user"])

    async def test_session_capacity_and_absolute_expiry(self):
        app = create_app(Settings(self.settings.nas_origin, self.settings.identity_origin,
                                  self.settings.public_origin, max_sessions=1, lifetime_seconds=1), self.upstream)
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://games.example",
                                    headers=self.client.headers) as browser:
            self.assertEqual((await browser.get("/api/account/session")).status_code, 200)
            browser.cookies.clear()
            self.assertEqual((await browser.get("/api/account/session")).status_code, 429)
            await asyncio.sleep(1.01)
            self.assertEqual((await browser.get("/api/account/session")).status_code, 200)

    def test_https_and_fixed_origins_are_required(self):
        for value in ("http://nas.example", "https://user:pass@nas.example", "https://nas.example/path"):
            with self.assertRaises(ValueError):
                Settings(value, self.settings.identity_origin, self.settings.public_origin)
        with self.assertRaises(ValueError):
            Settings(self.settings.nas_origin, self.settings.identity_origin, "http://games.example")


if __name__ == "__main__":
    unittest.main()
