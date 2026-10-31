import unittest

import httpx

from services.web_account.ai_app import create_app


class StandaloneAiTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.requests = []

        def provider(request):
            self.requests.append(request)
            return httpx.Response(200, json={"data": [{"id": "fixture-model"}]})

        self.provider = httpx.AsyncClient(transport=httpx.MockTransport(provider))
        app = create_app("https://games.example:8084", ["https://www.loomex.lol"], self.provider)
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://games.example:8084",
            headers={"Origin": "https://games.example:8084", "X-Board-Game-Request": "1",
                     "Authorization": "Bearer fixture-only", "X-BGA-AI-Target": "https://www.loomex.lol/v1/models"})

    async def asyncTearDown(self):
        await self.client.aclose()
        await self.provider.aclose()

    async def test_guest_byok_needs_no_old_session_and_drops_site_credentials(self):
        response = await self.client.get("/api/ai/request", headers={"Cookie": "private=fixture", "X-CSRF-Token": "site-token"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["data"][0]["id"], "fixture-model")
        self.assertEqual(self.requests[0].headers["authorization"], "Bearer fixture-only")
        self.assertFalse(self.requests[0].headers.get("cookie"))
        self.assertNotIn("x-csrf-token", self.requests[0].headers)
        self.assertNotIn("set-cookie", response.headers)

    async def test_untrusted_origin_and_missing_guard_are_rejected(self):
        for headers in ({"Origin": "https://evil.example"}, {"X-Board-Game-Request": ""}, {"Sec-Fetch-Site": "cross-site"}):
            response = await self.client.get("/api/ai/request", headers=headers)
            self.assertEqual(response.status_code, 403)
        self.assertEqual(self.requests, [])

    async def test_old_account_and_library_endpoints_do_not_exist(self):
        for path in ("/api/account/session", "/api/account/login", "/library/assets/catalog.json", "/api/comments/entries"):
            response = await self.client.get(path)
            self.assertEqual(response.status_code, 404)

    async def test_unsafe_provider_and_missing_key_are_rejected(self):
        response = await self.client.get("/api/ai/request", headers={"X-BGA-AI-Target": "https://127.0.0.1/v1/models"})
        self.assertEqual(response.status_code, 403)
        response = await self.client.get("/api/ai/request", headers={"Authorization": ""})
        self.assertEqual(response.status_code, 401)
        self.assertEqual(self.requests, [])
