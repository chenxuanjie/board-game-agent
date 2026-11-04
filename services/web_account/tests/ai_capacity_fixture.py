"""Test-only held upstream and process/cgroup metrics; never shipped in images."""
import asyncio
from pathlib import Path
import resource

import httpx
import ijson
from starlette.responses import JSONResponse
from starlette.routing import Route

import ai_app


class ObservedRelay(ai_app.AiRelay):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        global relay
        relay = self


class HeldUpstream(httpx.AsyncBaseTransport):
    def __init__(self):
        self.gate = asyncio.Event()

    async def handle_async_request(self, request):
        # Real Uvicorn ingress and production HTTPX request serialization.
        # Do not copy/buffer the payload in this measuring fixture.
        async for _ in request.stream:
            pass
        await self.gate.wait()
        return httpx.Response(200, json={'status': 'fixture-ok'})


ai_app.AiRelay = ObservedRelay
transport = HeldUpstream()
app = ai_app.create_app('https://fixture.test', ['https://www.loomex.lol'],
                       httpx.AsyncClient(transport=transport))


async def status(_):
    cgroup = Path('/sys/fs/cgroup')
    memory = {}
    for filename in ('memory.current', 'memory.peak', 'memory.events'):
        path = cgroup / filename
        if path.exists():
            memory[filename] = path.read_text().strip()
    return JSONResponse({'inflight': relay.inflight,
                         'reserved': relay.reserved_request_bytes,
                         'parser_version': ijson.__version__, 'parser_backend': ijson.backend,
                         'rss_peak_bytes': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024,
                         'cgroup': memory})


async def control(request):
    if request.path_params['action'] == 'release':
        transport.gate.set()
    elif relay.inflight == 0:
        transport.gate = asyncio.Event()
    else:
        return JSONResponse({'error': 'not idle'}, 409)
    return JSONResponse({'ok': True})


app.router.routes.extend([Route('/probe/status', status),
                         Route('/probe/{action}', control, methods=['POST'])])
