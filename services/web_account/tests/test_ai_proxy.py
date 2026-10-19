import asyncio
import json
import unittest

import httpx
from starlette.requests import Request

from services.web_account.app import Settings, create_app
from services.web_account.ai_proxy import AiRelay


class AiProxyTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.requests = []
        self.reply_status = 200
        self.reply_headers = {"content-type": "application/json", "set-cookie": "provider-secret=unused"}
        self.reply_body = b'{"data":[{"id":"test-model"}]}'
        self.timeout = False
        self.ai = httpx.AsyncClient(transport=httpx.MockTransport(self.provider))
        self.dsm = httpx.AsyncClient(transport=httpx.MockTransport(lambda _: self.fail("AI must not call DSM")))
        self.settings = Settings("https://nas.example:5001", "https://nas.example:5001", "https://games.example:18887")
        self.app = create_app(self.settings, self.dsm, self.ai)
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app),
            base_url=self.settings.public_origin, headers={"Origin": self.settings.public_origin,
            "X-Board-Game-Request": "1", "Authorization": "Bearer fixture-provider-key"})
        await self.client.get("/api/account/session")

    async def asyncTearDown(self):
        await self.client.aclose()
        await self.ai.aclose()
        await self.dsm.aclose()

    async def provider(self, request):
        self.requests.append(request)
        self.assertEqual(request.url.host, "www.loomex.lol")
        self.assertEqual(request.headers["authorization"], "Bearer fixture-provider-key")
        self.assertEqual(request.headers.get("cookie", ""), "")
        for name in ("x-syno-token", "x-bga-ai-target", "x-board-game-request", "origin"):
            self.assertNotIn(name, request.headers)
        if self.timeout:
            raise httpx.ReadTimeout("upstream error contains fixture-provider-key")
        return httpx.Response(self.reply_status, content=self.reply_body, headers=self.reply_headers)

    def target(self, path="models"):
        return {"X-BGA-AI-Target": "https://www.loomex.lol/v1/" + path}

    async def test_https_custom_port_cookie_and_guest_model_list(self):
        response = await self.client.get("/api/ai/request", headers={**self.target(), "X-Syno-Token": "must-not-forward"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["data"][0]["id"], "test-model")
        self.assertNotIn("set-cookie", response.headers)
        self.assertEqual(response.headers["cache-control"], "no-store")
        self.assertEqual(len(self.requests), 1)
        self.assertTrue(any(cookie.name == '__Host-bga_account' and cookie.secure for cookie in self.client.cookies.jar))

    async def test_chat_responses_and_compaction_preserve_request_and_response(self):
        for path in ("chat/completions", "responses", "responses/compact"):
            body = {"model": "test-model", "input": "规则问题", "stream": False}
            response = await self.client.post("/api/ai/request", headers=self.target(path), json=body)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(json.loads(self.requests[-1].content), body)
            self.assertTrue(str(self.requests[-1].url).endswith(path))

    async def test_sse_is_passed_without_synthetic_events_or_cookie_headers(self):
        self.reply_headers["content-type"] = "text/event-stream"
        self.reply_body = b'data: {"choices":[{"delta":{"content":"hello"}}]}\n\ndata: [DONE]\n\n'
        response = await self.client.post("/api/ai/request", headers=self.target("chat/completions"),
            json={"model": "test-model", "stream": True})
        self.assertEqual(response.content, self.reply_body)
        self.assertEqual(response.headers["x-accel-buffering"], "no")

    async def test_unsafe_targets_methods_and_untrusted_origins_never_reach_upstream(self):
        for target in ("https://192.168.1.55/v1/models", "https://www.loomex.lol.evil.example/v1/models",
                "https://www.loomex.lol@evil.example/v1/models", "http://www.loomex.lol/v1/models",
                "https://www.loomex.lol/v1/models?url=https://nas.example", "https://www.loomex.lol/v1/../models",
                "https://www.loomex.lol/v1/files", "https://www.loomex.lol/v1/%2e%2e/models"):
            response = await self.client.get("/api/ai/request", headers={"X-BGA-AI-Target": target})
            self.assertIn(response.status_code, (400, 403))
        response = await self.client.post("/api/ai/request", headers=self.target(), json={})
        self.assertEqual(response.status_code, 400)
        response = await self.client.get("/api/ai/request", headers={**self.target(), "Origin": "https://games.example:1887"})
        self.assertEqual(response.status_code, 403)
        self.assertFalse(self.requests)

    async def test_requires_site_session_and_a_key(self):
        self.client.cookies.clear()
        response = await self.client.get("/api/ai/request", headers=self.target())
        self.assertEqual(response.status_code, 401)
        await self.client.get("/api/account/session")
        response = await self.client.get("/api/ai/request", headers={**self.target(), "Authorization": ""})
        self.assertEqual(response.status_code, 401)
        self.assertFalse(self.requests)

    async def test_provider_errors_preserve_status_and_retry_after_without_redirecting(self):
        self.reply_status = 429
        self.reply_body = b'{"error":{"message":"limited fixture-provider-key"}}'
        self.reply_headers["retry-after"] = "5"
        response = await self.client.get("/api/ai/request", headers=self.target())
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.headers["retry-after"], "5")
        self.assertNotIn("fixture-provider-key", response.text)
        self.reply_status = 302
        self.reply_headers["location"] = "https://nas.example/private"
        response = await self.client.get("/api/ai/request", headers=self.target())
        self.assertEqual(response.status_code, 502)
        self.assertNotIn("location", response.headers)
        self.assertEqual(len(self.requests), 2)

    async def test_timeout_and_invalid_data_return_sanitized_retryable_errors(self):
        self.timeout = True
        response = await self.client.get("/api/ai/request", headers=self.target())
        self.assertEqual(response.status_code, 504)
        self.assertNotIn("fixture-provider-key", response.text)
        self.timeout = False
        self.reply_headers["content-type"] = "text/html"
        response = await self.client.get("/api/ai/request", headers=self.target())
        self.assertEqual(response.status_code, 502)
        response = await self.client.post("/api/ai/request", headers=self.target("responses"), json=[])
        self.assertEqual(response.status_code, 400)

    async def test_stream_cancellation_closes_provider_and_releases_slot(self):
        class SlowStream(httpx.AsyncByteStream):
            closed = False
            async def __aiter__(self):
                yield b"data: first\n\n"
                await asyncio.Event().wait()
            async def aclose(self):
                self.closed = True
        stream = SlowStream()
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200,
                headers={"content-type": "text/event-stream"}, stream=stream))) as client:
            relay = AiRelay(("https://www.loomex.lol",), client)
            scope = {"type": "http", "method": "GET", "path": "/api/ai/request",
                "headers": [(b"x-bga-ai-target", b"https://www.loomex.lol/v1/models"),
                    (b"authorization", b"Bearer test-key")]}
            async def receive():
                return {"type": "http.request", "body": b"", "more_body": False}
            response = await relay.forward(Request(scope, receive))
            iterator = response.body_iterator
            self.assertEqual(await anext(iterator), b"data: first\n\n")
            self.assertEqual(relay.inflight, 1)
            await iterator.aclose()
            self.assertTrue(stream.closed)
            self.assertEqual(relay.inflight, 0)
