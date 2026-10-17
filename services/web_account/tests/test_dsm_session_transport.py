"""Regression for live DSM 119: authentication must precede POST body parsing."""
import asyncio
import unittest
from urllib.parse import parse_qs

import httpx

from services.web_account.app import Dsm, Failure, NasSession, Settings


class DsmSessionTransportTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.requests = []
        self.client = httpx.AsyncClient(transport=httpx.MockTransport(self.dsm))
        self.client.cookies.set('id', 'stale-other-account', domain='nas.example', path='/')
        self.gateway = Dsm(Settings('https://nas.example:5001', 'https://canonical.example:5001',
                                    'https://games.example'), self.client)
        self.gateway.download_path = 'entry.cgi'
        self.first = NasSession('first-sid', 'first-token', 'entry.cgi', 'entry.cgi', 'first', 1001)
        self.second = NasSession('second-sid', 'second-token', 'entry.cgi', 'entry.cgi', 'second', 1002)

    async def asyncTearDown(self):
        await self.client.aclose()

    async def dsm(self, request):
        fields = {key: values[0] for key, values in parse_qs((await request.aread()).decode()).items()}
        self.requests.append(request)
        self.assertEqual(request.url.query, b'')
        self.assertEqual(request.method, 'POST')
        if fields['api'] == 'SYNO.API.Info':
            self.assertEqual(request.headers.get('cookie', ''), '')
            self.assertNotIn('x-syno-token', request.headers)
            return httpx.Response(200, json={'success': True, 'data': {}},
                                  headers={'Set-Cookie': 'id=poisoned-other-account; Path=/'})
        # Match the observed real NAS: form-only credentials are too late.
        identity = {
            ('id=first-sid', 'first-token'): 1001,
            ('id=second-sid', 'second-token'): 1002,
        }.get((request.headers.get('cookie'), request.headers.get('x-syno-token')))
        if identity is None:
            return httpx.Response(200, json={'success': False, 'error': {'code': 119}})
        self.assertNotIn('_sid', fields)
        self.assertNotIn('SynoToken', fields)
        await asyncio.sleep(0)  # Deliberately interleave shared-client requests.
        if fields['method'] == 'download':
            self.assertEqual(request.headers.get('range'), 'bytes=0-0')
            return httpx.Response(206, content=b'x', headers={'Content-Type': 'application/octet-stream',
                                                            'Content-Disposition': 'attachment'})
        return httpx.Response(200, json={'success': True, 'data': {'uid': identity}},
                              headers={'Set-Cookie': 'id=poisoned-other-account; Path=/'})

    async def test_body_only_sid_reproduces_119_but_request_headers_verify_identity(self):
        response = await self.client.post('https://nas.example:5001/webapi/entry.cgi',
                                          data={'api': 'SYNO.FileStation.Info', 'method': 'get', 'version': '2',
                                                '_sid': self.first.sid, 'SynoToken': self.first.token})
        self.assertEqual(response.json()['error']['code'], 119)
        self.assertEqual(await self.gateway.uid(self.first), 1001)

    async def test_concurrent_accounts_keep_identity_permission_and_logout_separate(self):
        self.assertEqual(await asyncio.gather(self.gateway.uid(self.first), self.gateway.uid(self.second)),
                         [1001, 1002])
        await asyncio.gather(self.gateway.readable(self.first, 'assets/catalog.json'),
                             self.gateway.readable(self.second, 'assets/catalog.json'))
        await asyncio.gather(self.gateway.revoke(self.first), self.gateway.revoke(self.second))
        self.assertEqual(len(self.requests), 6)

    async def test_server_cookie_jar_never_authenticates_anonymous_or_other_account_requests(self):
        await self.gateway.uid(self.first)
        await self.gateway.api('entry.cgi', {'api': 'SYNO.API.Info', 'method': 'query', 'version': '1'})
        self.assertEqual(await self.gateway.uid(self.second), 1002)

    async def test_missing_token_does_not_reuse_another_accounts_credentials(self):
        await self.gateway.uid(self.first)
        self.second.token = None
        with self.assertRaises(Failure) as failure:
            await self.gateway.uid(self.second)
        self.assertEqual(failure.exception.code, 'sessionRejected')
        self.assertEqual(self.requests[-1].headers['cookie'], 'id=second-sid')
        self.assertNotIn('x-syno-token', self.requests[-1].headers)

    async def test_invalid_cookie_and_token_values_never_reach_transport(self):
        for sid in ('sid;id=other', 'sid,other', 'sid\\other', 'sid"other', 'sid\r\nX-Test:bad', '会话'):
            with self.subTest(kind='sid', value=sid):
                self.first.sid = sid
                with self.assertRaises(Failure):
                    await self.gateway.uid(self.first)
        self.first.sid = 'first-sid'
        for token in ('token\r\nX-Test:bad', 'token value', '令牌'):
            with self.subTest(kind='token', value=token):
                self.first.token = token
                with self.assertRaises(Failure):
                    await self.gateway.readable(self.first, 'assets/catalog.json')
        self.assertEqual(self.requests, [])
