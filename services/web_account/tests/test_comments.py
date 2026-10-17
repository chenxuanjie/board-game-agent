import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from email.parser import BytesParser
from email.policy import default
from urllib.parse import parse_qs

import httpx

from services.web_account.app import Settings, create_app
from services.web_account.comments import Comments


class CommentsGatewayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.uid = os.getuid() if hasattr(os, 'getuid') and os.getuid() > 0 else 1001
        self.path = f'u{self.uid}/d' + 'a' * 32 + '.json'
        self.snapshot = json.dumps({'version': 1, 'uid': self.uid, 'device': 'd' + 'a' * 32,
            'operations': [{'id': 'c' + 'b' * 32, 'uid': self.uid, 'game': 'sample', 'action': 'publish',
                'revision': 1, 'at': '2026-10-17T00:00:00Z', 'author': '桌友', 'text': '公开评论',
                'root': None, 'replyTo': None, 'target': None, 'rating': 8, 'liked': False}]})
        self.calls = []
        self.expired = False
        self.denied_directory = False
        self.settings = Settings('https://nas.example:5001', 'https://nas.example:5001',
            'https://games.example', comments_root=str(self.root))
        self.upstream = httpx.AsyncClient(transport=httpx.MockTransport(self.dsm))
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(
            app=create_app(self.settings, self.upstream), raise_app_exceptions=False),
            base_url=self.settings.public_origin, headers={'X-Board-Game-Request': '1'})

    async def asyncTearDown(self):
        await self.client.aclose()
        await self.upstream.aclose()
        self.temp.cleanup()

    async def dsm(self, request):
        raw = await request.aread()
        upload = None
        if request.headers['content-type'].startswith('multipart/'):
            message = BytesParser(policy=default).parsebytes(
                b'Content-Type: ' + request.headers['content-type'].encode() + b'\r\n\r\n' + raw)
            fields = {}
            for part in message.iter_parts():
                name = part.get_param('name', header='content-disposition')
                if name == 'file':
                    upload = (part.get_filename(), part.get_payload(decode=True))
                else:
                    fields[name] = part.get_payload(decode=True).decode()
        else:
            fields = {k: v[0] for k, v in parse_qs(raw.decode()).items()}
        self.calls.append(fields)
        if fields['api'] != 'SYNO.API.Info' and fields['method'] != 'login':
            self.assertEqual(request.headers['cookie'], 'id=private-sid')
            self.assertEqual(request.headers['x-syno-token'], 'private-token')
        self.assertEqual(request.url.query, b'')
        if fields['api'] == 'SYNO.API.Info':
            data = {name: {'path': 'entry.cgi', 'minVersion': 1, 'maxVersion': 7}
                    for name in fields['query'].split(',')}
        elif fields['method'] == 'login':
            data = {'sid': 'private-sid', 'synotoken': 'private-token'}
        elif fields['api'] == 'SYNO.FileStation.Info':
            if self.expired:
                return httpx.Response(200, json={'success': False, 'error': {'code': 119}})
            data = {'uid': self.uid}
        elif fields['method'] == 'getinfo':
            path = json.loads(fields['path'])[0]
            relative = path.removeprefix(self.settings.comments_nas_path).lstrip('/')
            target = self.root / relative
            if self.denied_directory and relative == f'u{self.uid}':
                data = {'files': [{'path': path, 'code': 407}]}
            elif not target.exists():
                data = {'files': [{'path': path, 'code': 408}]}
            else:
                data = {'files': [{'path': path, 'isdir': target.is_dir(),
                                   'additional': {'owner': {'uid': self.uid}}}]}
        elif fields['method'] == 'create':
            self.assertEqual(fields['force_parent'], 'false')
            self.assertEqual(json.loads(fields['folder_path']), [self.settings.comments_nas_path])
            self.assertEqual(json.loads(fields['name']), [f'u{self.uid}'])
            (self.root / f'u{self.uid}').mkdir()
            data = {}
        elif fields['method'] == 'upload':
            self.assertEqual(fields['create_parents'], 'false')
            self.assertEqual(fields['path'], f'{self.settings.comments_nas_path}/u{self.uid}')
            (self.root / f'u{self.uid}' / upload[0]).write_bytes(upload[1])
            data = {}
        else:
            data = {}
        return httpx.Response(200, json={'success': True, 'data': data})

    async def login(self):
        await self.client.get('/api/account/session')
        response = await self.client.post('/api/account/login', json={'account': 'test', 'password': 'test'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['user']['uid'], self.uid)

    async def save(self, content=None, path=None):
        return await self.client.post('/api/comments/file', params={'path': path or self.path},
                                      json={'content': self.snapshot if content is None else content})

    async def test_guest_can_list_and_read_existing_native_snapshot_without_dsm(self):
        if not hasattr(os, 'getuid') or os.getuid() == 0:
            self.skipTest('Requires non-root Unix owner metadata, as in the runtime image')
        file = self.root / self.path
        file.parent.mkdir()
        file.write_text(self.snapshot)
        self.assertEqual((await self.client.get('/api/comments/entries')).json()['entries'][0]['name'], f'u{self.uid}')
        listing = await self.client.get('/api/comments/entries', params={'path': f'u{self.uid}'})
        self.assertEqual(listing.json()['entries'][0]['ownerUid'], self.uid)
        response = await self.client.get('/api/comments/file', params={'path': self.path})
        self.assertEqual(response.json()['content'], self.snapshot)
        self.assertEqual(self.calls, [])

    async def test_guest_writes_and_cross_origin_reads_are_rejected(self):
        self.assertEqual((await self.save()).status_code, 401)
        self.assertEqual((await self.client.get('/api/comments/entries', headers={'Origin': 'https://evil.example'})).status_code, 403)
        self.assertEqual(self.calls, [])

    async def test_unreadable_comment_mount_is_sanitized(self):
        with patch.object(Comments, 'entries', side_effect=PermissionError('private physical path')):
            response = await self.client.get('/api/comments/entries')
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json(), {'error': 'commentsUnreadable'})

    async def test_signed_in_write_roundtrip_and_logout_preserves_public_read(self):
        if not hasattr(os, 'getuid') or os.getuid() == 0:
            self.skipTest('Requires non-root Unix owner metadata')
        await self.login()
        self.assertEqual((await self.save()).status_code, 200)
        await self.client.post('/api/account/logout')
        self.assertEqual((await self.save()).status_code, 401)
        read = await self.client.get('/api/comments/file', params={'path': self.path})
        self.assertEqual(read.json()['content'], self.snapshot)

    async def test_forged_uid_or_other_accounts_path_never_uploads(self):
        await self.login()
        self.assertEqual((await self.save(path='u999/d' + 'a' * 32 + '.json')).status_code, 400)
        data = json.loads(self.snapshot)
        data['operations'][0]['uid'] = 999
        self.assertEqual((await self.save(json.dumps(data))).status_code, 400)
        self.assertFalse(any(c['method'] in ('upload', 'create') for c in self.calls))

    async def test_denied_directory_never_triggers_initialization(self):
        await self.login()
        self.denied_directory = True
        self.assertEqual((await self.save()).status_code, 403)
        self.assertFalse(any(c['method'] in ('upload', 'create') for c in self.calls))

    async def test_expired_session_never_uploads(self):
        await self.login()
        self.expired = True
        self.assertEqual((await self.save()).status_code, 401)
        self.assertFalse(any(c['method'] in ('upload', 'create') for c in self.calls))

    async def test_arbitrary_paths_and_symlink_cannot_expose_private_files(self):
        for path in ('../private', 'u1/../../private', 'u1/.env', 'u1/d' + 'a' * 32 + '.json/extra'):
            self.assertEqual((await self.client.get('/api/comments/file', params={'path': path})).status_code, 404)
        target = self.root / f'u{self.uid}'
        target.mkdir()
        private = self.root / 'secret'
        private.write_text(self.snapshot)
        try:
            (self.root / self.path).symlink_to(private)
        except OSError:
            return
        self.assertEqual((await self.client.get('/api/comments/file', params={'path': self.path})).status_code, 403)
