"""Opt-in real HTTP capacity check using an existing production relay image.

BGA_AI_TEST_IMAGE=board-game-agent-web-ai:local-layer-test
No image build, registry pull, credentials or NAS access is performed.
"""
import asyncio
import json
import os
from pathlib import Path
import subprocess
import time
import unittest
from uuid import uuid4

import httpx

ROOT = Path(__file__).resolve().parents[2]
IMAGE = os.getenv('BGA_AI_TEST_IMAGE')


@unittest.skipUnless(IMAGE, 'Select an existing relay image with BGA_AI_TEST_IMAGE')
class AiContainerCapacityTests(unittest.TestCase):
    def test_real_http_capacity_within_256_mib(self):
        docker = ['wsl', '-d', 'Ubuntu', '--exec', 'docker'] if os.name == 'nt' else ['docker']

        def run(*args):
            return subprocess.check_output([*docker, *args], text=True, stderr=subprocess.STDOUT,
                                           timeout=45).strip()

        def linux(path):
            if os.name == 'nt':
                return subprocess.check_output(['wsl', '-d', 'Ubuntu', '--exec', 'wslpath', '-a', str(path)],
                                               text=True, timeout=10).strip()
            return str(path)

        run('image', 'inspect', IMAGE)
        name = 'bga-ai-capacity-' + uuid4().hex[:10]
        arguments = ['run', '-d', '--name', name, '--pull=never', '--memory=256m', '--memory-swap=256m',
                     '--pids-limit=32', '--read-only', '--cap-drop=ALL', '--security-opt=no-new-privileges:true',
                     '--tmpfs=/tmp:rw,nosuid,nodev,size=32m', '-p', '127.0.0.1::8000']
        for source, target in [('services/web_account/ai_app.py', '/app/ai_app.py'),
                               ('services/web_account/ai_proxy.py', '/app/ai_proxy.py'),
                               ('services/web_account/tests/ai_capacity_fixture.py', '/app/capacity_fixture.py')]:
            arguments += ['-v', f'{linux(ROOT / source)}:{target}:ro']
        # Existing image tests may overlay the exact hash-verified new wheel,
        # extracted locally; CI with an updated runtime image needs no overlay.
        if dependencies := os.getenv('BGA_AI_TEST_DEPS'):
            arguments += ['-v', f'{linux(Path(dependencies).resolve())}:/opt/probe-deps:ro',
                          '-e', 'PYTHONPATH=/opt/probe-deps']
        arguments += [IMAGE, 'uvicorn', 'capacity_fixture:app', '--host', '0.0.0.0', '--port', '8000',
                      '--workers', '1', '--no-access-log', '--no-proxy-headers']
        try:
            run(*arguments)
            port = run('port', name, '8000/tcp').rsplit(':', 1)[1]
            origin = f'http://127.0.0.1:{port}'
            with httpx.Client(base_url=origin, trust_env=False, timeout=2) as client:
                for attempt in range(60):
                    try:
                        if client.get('/healthz').status_code == 200:
                            break
                    except httpx.HTTPError:
                        pass
                    time.sleep(.1)
                else:
                    self.fail(run('logs', name))
            result = asyncio.run(self.exercise(origin))
            state = json.loads(run('inspect', '--format={{json .State}}', name))
            self.assertFalse(state['OOMKilled'])
            self.assertTrue(state['Running'])
            result['container'] = {'oom_killed': state['OOMKilled'], 'running': state['Running']}
            report = ROOT / '.local' / 'a03-capacity.json'
            report.parent.mkdir(exist_ok=True)
            report.write_text(json.dumps(result, indent=2), encoding='utf-8')
            # Leave at least 32 MiB below the deployment's hard memory limit.
            self.assertLess(result['rss_peak_bytes'], 224 * 1024 * 1024, result)
            peak = result['cgroup'].get('memory.peak', '')
            if peak:
                self.assertLess(int(peak), 224 * 1024 * 1024, result)
            events = result['cgroup'].get('memory.events', '')
            self.assertNotRegex(events, r'(?m)^oom(?:_kill|_group_kill)? [1-9]')
        finally:
            run('rm', '-f', name)

    async def exercise(self, origin):
        headers = {'Origin': 'https://fixture.test', 'X-Board-Game-Request': '1',
                   'Authorization': 'Bearer capacity-fixture', 'Content-Type': 'application/json',
                   'X-BGA-AI-Target': 'https://www.loomex.lol/v1/responses'}
        rounds = []
        async with httpx.AsyncClient(base_url=origin, trust_env=False, timeout=35,
                                     limits=httpx.Limits(max_connections=16)) as client:
            async def round_trip(body, expected):
                self.assertEqual((await client.post('/probe/reset')).status_code, 200)
                tasks = [asyncio.create_task(client.post('/api/ai/request', headers=headers, content=body))
                         for _ in range(8)]
                try:
                    for _ in range(200):
                        status = (await client.get('/probe/status')).json()
                        completed = [task for task in tasks if task.done()]
                        if status['inflight'] == expected and len(completed) == 8 - expected:
                            break
                        await asyncio.sleep(.05)
                    else:
                        self.fail(f'Admission did not settle: {status}, finished={len(completed)}')
                    self.assertLessEqual(status['reserved'], 16 * 1024 * 1024)
                    for task in completed:
                        response = task.result()
                        self.assertEqual((response.status_code, response.json()['code']), (429, 'aiBusy'))
                        self.assertEqual(response.headers.get('retry-after'), '1')
                    self.assertEqual((await client.post('/probe/release')).status_code, 200)
                    responses = await asyncio.gather(*tasks)
                    self.assertEqual(sum(r.status_code == 200 for r in responses), expected)
                    idle = (await client.get('/probe/status')).json()
                    self.assertEqual((idle['inflight'], idle['reserved']), (0, 0))
                    rounds.append({'bytes': len(body), 'accepted': expected, 'busy': 8 - expected})
                finally:
                    for task in tasks:
                        task.cancel()
                    await asyncio.gather(*tasks, return_exceptions=True)

            await round_trip(b'{"input":"' + b'x' * (16 * 1024 * 1024 - 128) + b'"}', 1)
            # A non-BMP character forces Python's worst-case four-byte strings.
            await round_trip(b'{"input":"' + b'x' * (16 * 1024 * 1024 - 128) + '😀'.encode() + b'"}', 1)
            await round_trip(b'{"input":"' + b'x' * (2 * 1024 * 1024 - 128) + b'"}', 8)
            # Reuse a warmed process after concurrency has fragmented its heap.
            await round_trip(b'{"input":"' + b'x' * (16 * 1024 * 1024 - 128) + '😀'.encode() + b'"}', 1)
            # The byte budget is not enough without an object-count guard.
            complex_body = b'{"input":[' + b'{},' * 100000 + b'{}]}'
            response = await client.post('/api/ai/request', headers=headers, content=complex_body)
            self.assertEqual((response.status_code, response.json()['code']), (413, 'aiRequestTooComplex'))
            result = (await client.get('/probe/status')).json()
            self.assertEqual((result['parser_version'], result['parser_backend']), ('3.6.0', 'yajl2_c'))
            self.assertEqual((result['inflight'], result['reserved']), (0, 0))
            result['rounds'] = rounds
            return result
