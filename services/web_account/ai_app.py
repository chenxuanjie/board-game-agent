"""Standalone BYOK relay. It has no account, NAS or library endpoints."""
from contextlib import asynccontextmanager
import os
from urllib.parse import urlsplit

import httpx
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route

try:
    from .ai_proxy import AiRelay, AiRelayError
except ImportError:
    from ai_proxy import AiRelay, AiRelayError


def checked_origin(value):
    uri = urlsplit(value)
    if (uri.scheme != "https" or not uri.hostname or uri.username or uri.password
            or uri.path not in ("", "/") or uri.query or uri.fragment):
        raise ValueError("A fixed HTTPS origin without credentials or path is required")
    port = uri.port
    return f"https://{uri.hostname.lower()}" + (f":{port}" if port not in (None, 443) else "")


def create_app(public_origin=None, allowed_origins=None, upstream=None):
    public_origin = checked_origin(public_origin or os.environ["WEB_PUBLIC_ORIGIN"])
    if allowed_origins is None:
        allowed_origins = os.getenv("AI_ALLOWED_ORIGINS", "https://api.openai.com,https://api.deepseek.com,https://www.loomex.lol,https://loomex.lol").split(",")
    allowed_origins = tuple(checked_origin(site.strip()) for site in allowed_origins if site.strip())
    if not 1 <= len(allowed_origins) <= 16:
        raise ValueError("Configure between one and sixteen trusted AI origins")
    owned = upstream is None
    upstream = upstream or httpx.AsyncClient(
        timeout=httpx.Timeout(35, connect=10, read=180, pool=3),
        follow_redirects=False, trust_env=False,
        limits=httpx.Limits(max_connections=8, max_keepalive_connections=4),
    )
    relay = AiRelay(allowed_origins, upstream)

    @asynccontextmanager
    async def lifespan(_):
        try:
            yield
        finally:
            if owned:
                await upstream.aclose()

    async def request_ai(request):
        if (request.headers.get("x-board-game-request") != "1"
                or request.headers.get("origin", public_origin) != public_origin
                or request.headers.get("sec-fetch-site") == "cross-site"):
            return JSONResponse({"code": "aiOriginDenied"}, status_code=403)
        return await relay.forward(request)

    async def failure(_, error):
        return JSONResponse({"code": error.code, "message": error.message}, status_code=error.status,
                            headers={"Retry-After": "1"} if error.status == 429 else None)

    async def unexpected(_, __):
        return JSONResponse({"code": "aiUnavailable"}, status_code=502)

    async def health(_):
        return JSONResponse({"status": "ok"})

    return Starlette(
        routes=[Route("/healthz", health), Route("/api/ai/request", request_ai, methods=["GET", "POST"])],
        exception_handlers={AiRelayError: failure, Exception: unexpected}, lifespan=lifespan,
    )
