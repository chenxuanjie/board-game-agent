"""Native-compatible FileStation records, isolated users, and failure injection."""
import asyncio
import json
import unittest
from email.parser import BytesParser
from email.policy import default
from urllib.parse import parse_qs

import httpx
from services.web_account.app import Settings, create_app, Failure
from services.web_account.account_files import AccountFiles


class AccountFilesTests(unittest.IsolatedAsyncioTestCase):
    async def test_public_entry_optional_revision_preserves_owner_and_legacy_fallback(self):
        async def call(api, method, fields):
            self.assertEqual(json.loads(fields['additional']), ['owner', 'size', 'time'])
            path = self.files.public_root + '/u1001/d' + 'b' * 32 + '.json'
            return {'total': 1, 'files': [{'path': path, 'name': path.rsplit('/', 1)[-1],
                'isdir': False, 'additional': {'owner': {'uid': 1001}, 'size': 123,
                'time': {'mtime': 10, 'ctime': 11}}}]}
        entries = await self.files.entries(call, 'public', 'u1001')
        self.assertEqual(json.loads(entries[0]['revision']), [1001, 123, 10, 11])
        self.assertEqual(entries[0]['ownerUid'], 1001)

    async def asyncSetUp(self):
        self.settings = Settings('https://nas.example:5001', 'https://identity.example:5001', 'https://games.example')
        self.files = AccountFiles(self.settings, Failure)
        self.objects = {'/home': (True, 1001, None), self.files.public_root: (True, 1001, None)}
        self.calls, self.denied, self.expired = [], None, False
        self.hold = None
        self.upstream = httpx.AsyncClient(transport=httpx.MockTransport(self.dsm))
        self.app = create_app(self.settings, self.upstream)
        self.client = self.new_client()
        await self.login(self.client, 1001)

    def new_client(self):
        return httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app, raise_app_exceptions=False),
            base_url=self.settings.public_origin, headers={'X-Board-Game-Request': '1', 'X-BGA-Account-UID': '1001'})

    async def asyncTearDown(self):
        await self.client.aclose()
        await self.upstream.aclose()

    async def login(self, client, uid):
        await client.get('/api/account/session')
        response = await client.post('/api/account/login', json={'account': str(uid), 'password': 'fixture'})
        self.assertEqual(response.status_code, 200)

    async def dsm(self, request):
        raw = await request.aread()
        upload = None
        if request.headers['content-type'].startswith('multipart/'):
            message = BytesParser(policy=default).parsebytes(b'Content-Type: ' + request.headers['content-type'].encode() + b'\r\n\r\n' + raw)
            fields = {}
            for part in message.iter_parts():
                name = part.get_param('name', header='content-disposition')
                if name == 'file':
                    upload = (part.get_filename(), part.get_payload(decode=True).decode())
                else:
                    fields[name] = part.get_payload(decode=True).decode()
        else:
            fields = {k: v[0] for k, v in parse_qs(raw.decode()).items()}
        self.calls.append(fields)
        self.assertEqual(request.url.query, b'')
        api, method = fields['api'], fields['method']
        def error(code):
            return httpx.Response(200, json={'success': False, 'error': {'code': code}})
        if api == 'SYNO.API.Info':
            data = {name: {'path': 'entry.cgi', 'minVersion': 1, 'maxVersion': 7} for name in fields['query'].split(',')}
        elif method == 'login':
            data = {'sid': 'sid-' + fields['account'], 'synotoken': 'token-' + fields['account']}
        else:
            uid = int(request.headers['cookie'].removeprefix('id=sid-'))
            self.assertEqual(request.headers['x-syno-token'], f'token-{uid}')
            if api == 'SYNO.FileStation.Info':
                return error(119) if self.expired else httpx.Response(200, json={'success': True, 'data': {'uid': uid}})
            if self.hold and method == 'getinfo':
                entered, release = self.hold
                entered.set()
                await release.wait()
            if method == 'getinfo':
                path = json.loads(fields['path'])[0]
                obj = self.objects.get(path)
                data = {'files': [{'path': path, 'code': 407 if path == self.denied else 408} if obj is None or path == self.denied else
                                  {'path': path, 'name': path.rsplit('/', 1)[-1], 'isdir': obj[0], 'additional': {'owner': {'uid': obj[1]}}}]}
            elif method == 'list':
                path = fields['folder_path']
                if path == self.denied:
                    return error(407)
                if path not in self.objects:
                    return error(408)
                children = []
                for name, obj in sorted(self.objects.items()):
                    if name.rsplit('/', 1)[0] == path:
                        children.append({'path': name, 'name': name.rsplit('/', 1)[-1], 'isdir': obj[0], 'additional': {'owner': {'uid': obj[1]}}})
                offset, limit = int(fields['offset']), int(fields['limit'])
                data = {'files': children[offset:offset + limit], 'total': len(children)}
            elif method == 'create':
                self.assertEqual(fields['force_parent'], 'false')
                parent, name = json.loads(fields['folder_path'])[0], json.loads(fields['name'])[0]
                self.assertIn(parent, self.objects)
                self.objects[parent + '/' + name] = (True, uid, None)
                data = {}
            elif method == 'upload':
                self.assertEqual(fields['create_parents'], 'false')
                self.assertIn(fields['path'], self.objects)
                path = fields['path'] + '/' + upload[0]
                if fields['overwrite'] == 'true' or path not in self.objects:
                    self.objects[path] = (False, uid, upload[1])
                data = {}
            elif method == 'download':
                path = json.loads(fields['path'])[0]
                if path not in self.objects:
                    return error(408)
                return httpx.Response(200, content=self.objects[path][2].encode(), headers={'Content-Disposition': 'attachment; filename=record.json'})
            else:
                data = {}
        return httpx.Response(200, json={'success': True, 'data': data})

    def operation(self, uid=1001, sequence=1):
        return {'protocolVersion': 1, 'datasetId': self.files.scope(uid), 'deviceId': 'd' + 'a' * 32,
                'sequence': sequence, 'operationId': 'd' + 'a' * 32 + f'_{sequence}', 'logicalClock': sequence,
                'entityType': 'favorite', 'entityId': 'catan', 'operation': 'upsert', 'payload': {'gameSlug': 'catan'},
                'parents': [], 'changedAt': '2026-10-18T00:00:00Z', 'payloadHash': 'sha256:' + 'a' * 64}

    def operation_path(self, sequence=1):
        return 'operations/d' + 'a' * 32 + f'.{sequence:016d}.json'

    async def entries(self, lane='private', path='operations', client=None):
        return await (client or self.client).get(f'/api/sync/{lane}/entries', params={'path': path})

    async def save(self, lane='private', path=None, content=None):
        return await self.client.post(f'/api/sync/{lane}/file', params={'path': path or self.operation_path()},
            json={'content': content if content is not None else json.dumps(self.operation())})

    async def test_private_initialization_and_immutable_native_record_roundtrip(self):
        self.assertEqual((await self.entries()).json(), {'entries': []})
        self.assertEqual((await self.save()).status_code, 200)
        response = await self.client.get('/api/sync/private/file', params={'path': self.operation_path()})
        self.assertEqual(json.loads(response.json()['content']), self.operation())
        self.assertEqual((await self.save()).status_code, 200)  # Retry is idempotent.
        changed = self.operation(); changed['entityId'] = 'splendor'
        self.assertEqual((await self.save(content=json.dumps(changed))).status_code, 409)
        self.assertEqual(json.loads(self.objects[self.files.private_root + '/' + self.operation_path()][2]), self.operation())
        self.assertTrue(all(c['name'] != '["d' + 'a' * 32 + '"]' for c in self.calls if c['method'] == 'create'))

    async def test_public_snapshot_and_owner_metadata_match_native_protocol(self):
        path = 'u1001/d' + 'a' * 32 + '.json'
        text = json.dumps({'version': 1, 'uid': 1001, 'device': 'd' + 'a' * 32, 'operations': [self.operation()]})
        self.assertEqual((await self.save('public', path, text)).status_code, 200)
        listing = await self.entries('public', 'u1001')
        self.assertEqual(listing.json()['entries'][0]['ownerUid'], 1001)
        response = await self.client.get('/api/sync/public/file', params={'path': path})
        self.assertEqual(response.json()['content'], text)
        self.objects[self.files.public_root + '/' + path] = (False, 2002, text)
        self.assertEqual((await self.client.get('/api/sync/public/file', params={'path': path})).status_code, 403)

    async def test_cross_account_paths_scopes_and_private_payload_in_public_are_rejected(self):
        await self.entries()
        before = len(self.calls)
        self.assertEqual((await self.save(content=json.dumps(self.operation(uid=2002)))).status_code, 400)
        for path in ('../private', '/home/other', 'operations/../other.json', 'operations/d' + 'a' * 32 + '/0000000000000001.json'):
            self.assertEqual((await self.save(path=path)).status_code, 400)
        op = self.operation(); op['entityType'] = 'conversation'
        text = json.dumps({'version': 1, 'uid': 1001, 'device': 'd' + 'a' * 32, 'operations': [op]})
        self.assertEqual((await self.save('public', 'u1001/d' + 'a' * 32 + '.json', text)).status_code, 400)
        self.assertEqual(len(self.calls), before)

    async def test_denied_directory_never_initializes_and_expired_session_never_writes(self):
        self.denied = self.files.private_root + '/operations'
        self.assertEqual((await self.entries()).status_code, 403)
        self.assertFalse(any(c['method'] == 'create' for c in self.calls))
        self.expired = True
        self.assertEqual((await self.save()).status_code, 401)
        self.assertFalse(any(c['method'] == 'upload' for c in self.calls))

    async def test_legacy_operation_directories_are_read_only(self):
        path = 'operations/d' + 'a' * 32 + '/0000000000000001.json'
        self.objects[self.files.private_root + '/' + path] = (False, 1001, json.dumps(self.operation()))
        response = await self.client.get('/api/sync/private/file', params={'path': path})
        self.assertEqual(response.status_code, 200)
        self.assertEqual((await self.save(path=path)).status_code, 400)

    async def test_guest_cross_origin_and_another_tabs_identity_are_rejected(self):
        for headers in ({'X-BGA-Account-UID': '2002'}, {'Origin': 'https://evil.example'}):
            response = await self.client.get('/api/sync/private/entries', params={'path': 'operations'}, headers=headers)
            self.assertIn(response.status_code, (401, 403))
        other = self.new_client()
        try:
            self.assertEqual((await self.entries(client=other)).status_code, 401)
        finally:
            await other.aclose()

    async def test_logout_mid_initialization_cannot_continue_creating_directories(self):
        entered, release = asyncio.Event(), asyncio.Event()
        self.hold = entered, release
        task = asyncio.create_task(self.entries())
        await asyncio.wait_for(entered.wait(), 2)
        await self.client.post('/api/account/logout')
        release.set()
        self.assertEqual((await task).status_code, 401)
        self.assertFalse(any(c['method'] == 'create' for c in self.calls))

    async def test_pagination_does_not_drop_native_operations(self):
        await self.entries()
        for sequence in range(1, 102):
            self.objects[self.files.private_root + '/' + self.operation_path(sequence)] = (False, 1001, '{}')
        response = await self.entries()
        self.assertEqual(len(response.json()['entries']), 101)
        self.assertTrue(any(c.get('offset') == '100' for c in self.calls))
