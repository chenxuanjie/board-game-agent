"""Admission and memory-shape regressions for the standalone BYOK relay."""
import asyncio
import json
import tempfile
import unittest
from unittest.mock import patch

import httpx
from starlette.requests import ClientDisconnect, Request

from services.web_account.ai_proxy import AiRelay, AiRelayError


def request(body=b'{}', *, length=True, receive=None):
    headers = [(b'x-bga-ai-target', b'https://www.loomex.lol/v1/responses'),
               (b'authorization', b'Bearer fixture'),
               (b'content-type', b'application/json')]
    if length is not False:
        headers.append((b'content-length', str(len(body) if length is True else length).encode()))

    async def read():
        return {'type': 'http.request', 'body': body, 'more_body': False}

    return Request({'type': 'http', 'method': 'POST', 'path': '/api/ai/request',
                    'headers': headers}, receive or read)


class AiCapacityTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.streams = []
        self.files = []
        temporary_file = tempfile.TemporaryFile

        def opened(*args, **kwargs):
            body = temporary_file(*args, **kwargs)
            self.files.append(body)
            return body

        patcher = patch('services.web_account.ai_proxy.tempfile.TemporaryFile', side_effect=opened)
        patcher.start()
        self.addCleanup(patcher.stop)

        class Stream(httpx.AsyncByteStream):
            closed = False
            async def __aiter__(self):
                yield b'{}'
            async def aclose(self):
                self.closed = True

        async def provider(_):
            stream = Stream()
            self.streams.append(stream)
            return httpx.Response(200, headers={'content-type': 'application/json'}, stream=stream)

        self.client = httpx.AsyncClient(transport=httpx.MockTransport(provider))
        self.relay = AiRelay(['https://www.loomex.lol'], self.client)

    async def asyncTearDown(self):
        await self.client.aclose()
        self.assertTrue(all(body.closed for body in self.files), 'Temporary upload file leaked')

    async def assert_failure(self, req, code, status):
        with self.assertRaises(AiRelayError) as raised:
            await self.relay.forward(req)
        self.assertEqual((raised.exception.code, raised.exception.status), (code, status))

    async def test_byte_budget_rejects_before_read_and_recovers_after_close(self):
        self.relay.request_bytes_budget = 12
        one = await self.relay.forward(request(b'{"a":1}'))
        received = False

        async def read():
            nonlocal received
            received = True
            self.fail('Rejected request body must not be read')

        await self.assert_failure(request(b'{"b":2}', receive=read), 'aiBusy', 429)
        self.assertFalse(received)
        self.assertEqual(self.relay.reserved_request_bytes, 7)
        await one.cleanup()
        await one.cleanup()  # Idempotent: never return a reservation twice.
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))
        two = await self.relay.forward(request(b'{"b":2}'))
        await two.cleanup()
        self.assertTrue(all(stream.closed for stream in self.streams))

    async def test_small_requests_keep_eight_stream_slots(self):
        responses = [await self.relay.forward(request()) for _ in range(8)]
        await self.assert_failure(request(), 'aiBusy', 429)
        self.assertEqual(self.relay.reserved_request_bytes, 16)
        for response in responses:
            await response.cleanup()
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))

    async def test_unknown_length_reserves_full_size_and_does_not_wait_for_memory(self):
        response = await self.relay.forward(request(length=False))
        self.assertEqual(self.relay.reserved_request_bytes, self.relay.request_limit)
        await self.assert_failure(request(length=False), 'aiBusy', 429)
        await response.cleanup()
        self.assertEqual(self.relay.reserved_request_bytes, 0)

    async def test_invalid_body_lengths_and_json_return_reservations(self):
        for req, code, status in [
            (request(length=self.relay.request_limit + 1), 'aiRequestTooLarge', 413),
            (request(length='bad'), 'aiInvalidRequest', 400),
            (request(length=1), 'aiInvalidRequest', 400),
            (request(length=3), 'aiInvalidRequest', 400),
            (request(b'[]'), 'aiInvalidRequest', 400),
            (request(b'{invalid}'), 'aiInvalidRequest', 400),
            (request(b''), 'aiInvalidRequest', 400),
            (request(b'{} {}'), 'aiInvalidRequest', 400),
            (request(b'{"a":'), 'aiInvalidRequest', 400),
            (request(b'{"a":"\xff"}'), 'aiInvalidRequest', 400),
            (request(b'{"a":NaN}'), 'aiInvalidRequest', 400),
            (request('{"a":1}'.encode('utf-16')), 'aiInvalidRequest', 400),
        ]:
            await self.assert_failure(req, code, status)
            self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))
        response = await self.relay.forward(request())
        await response.cleanup()

    async def test_complexity_guard_precedes_object_allocation_and_ignores_quoted_syntax(self):
        self.relay.json_structure_limit = 20
        self.relay.json_depth_limit = 8
        for body in (b'{"a":[' + b'{},' * 20 + b'{}]}', b'{"a":' + b'[' * 9 + b'0' + b']' * 9 + b'}'):
            await self.assert_failure(request(body), 'aiRequestTooComplex', 413)
        quoted = json.dumps({'input': '\\"{}[],:' * 1000 + '中文😀'}).encode()
        response = await self.relay.forward(request(quoted))
        await response.cleanup()
        self.assertEqual(self.relay.reserved_request_bytes, 0)

    async def test_cancel_during_upload_releases_reserved_bytes(self):
        entered = asyncio.Event()

        async def receive():
            entered.set()
            await asyncio.Event().wait()

        task = asyncio.create_task(self.relay.forward(request(receive=receive)))
        await entered.wait()
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))

    async def test_timeout_and_upstream_failure_release_capacity(self):
        async def failed(_):
            raise httpx.ConnectError('fixture failure')
        async with httpx.AsyncClient(transport=httpx.MockTransport(failed)) as client:
            self.relay.client = client
            await self.assert_failure(request(), 'aiNetwork', 502)
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))
        self.relay.total_seconds = .01

        async def stalled():
            await asyncio.Event().wait()

        await self.assert_failure(request(receive=stalled), 'aiTimeout', 504)
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))

    async def test_response_disconnect_releases_capacity(self):
        response = await self.relay.forward(request())

        async def send(_):
            raise OSError('fixture disconnect')

        with self.assertRaises(ClientDisconnect):
            await response({'type': 'http', 'asgi': {'spec_version': '2.4'}}, None, send)
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))
        self.assertTrue(self.streams[0].closed)

    async def test_cancel_while_waiting_for_headers_releases_admission(self):
        entered = asyncio.Event()

        class Transport(httpx.AsyncBaseTransport):
            async def handle_async_request(self, req):
                async for _ in req.stream:
                    pass
                entered.set()
                await asyncio.Event().wait()

        async with httpx.AsyncClient(transport=Transport()) as client:
            self.relay.client = client
            task = asyncio.create_task(self.relay.forward(request()))
            await entered.wait()
            self.assertEqual(self.relay.reserved_request_bytes, 2)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))
        self.relay.client = self.client
        response = await self.relay.forward(request())
        await response.cleanup()

    async def test_upstream_stream_failure_closes_body_and_releases_budget(self):
        class FailedStream(httpx.AsyncByteStream):
            closed = False
            async def __aiter__(self):
                yield b'first'
                raise httpx.ReadError('fixture read failure')
            async def aclose(self):
                self.closed = True

        stream = FailedStream()
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(
                200, stream=stream, headers={'content-type': 'text/event-stream'}))) as client:
            self.relay.client = client
            response = await self.relay.forward(request())
            self.assertEqual(await anext(response.body_iterator), b'first')
            with self.assertRaises(AiRelayError) as raised:
                await anext(response.body_iterator)
            self.assertEqual(raised.exception.code, 'aiStreamInterrupted')
        self.assertTrue(stream.closed)
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))

    async def test_upstream_close_failure_still_releases_file_and_budget(self):
        response = await self.relay.forward(request())

        async def failed_close():
            raise RuntimeError('fixture close failure')

        self.streams[0].aclose = failed_close
        with self.assertRaises(RuntimeError):
            await response.cleanup()
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))

    async def test_tempfile_creation_failure_returns_admission_capacity(self):
        with patch('services.web_account.ai_proxy.tempfile.TemporaryFile', side_effect=OSError('fixture full')):
            with self.assertRaises(OSError):
                await self.relay.forward(request())
        self.assertEqual((self.relay.inflight, self.relay.reserved_request_bytes), (0, 0))
