"""Same-origin Web preview: one application API plus the existing bounded BYOK relay."""

import argparse
import asyncio
import hashlib
import sys
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import urlsplit

import httpx
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.responses import FileResponse, JSONResponse, Response, StreamingResponse
from starlette.routing import Mount, Route
from starlette.staticfiles import StaticFiles

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from services.web_account.ai_proxy import AiRelay, AiRelayError  # noqa: E402

HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
}
REQUEST_HEADERS = {
    "accept",
    "accept-encoding",
    "authorization",
    "content-type",
    "cookie",
    "origin",
    "x-csrf-token",
    "x-app-id",
    "x-board-game-request",
    "x-user-agent",
    "x-powersync-user-agent",
    "user-agent",
    "range",
    "if-range",
    "if-none-match",
    "if-modified-since",
    "sec-fetch-site",
}
LIMIT = 16 * 1024 * 1024


class IsolationHeaders:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        async def with_headers(message):
            if message["type"] == "http.response.start":
                headers = [
                    (k, v)
                    for k, v in message["headers"]
                    if k.lower()
                    not in {
                        b"cross-origin-opener-policy",
                        b"cross-origin-embedder-policy",
                        b"x-content-type-options",
                    }
                ]
                message = {
                    **message,
                    "headers": headers
                    + [
                        (b"cross-origin-opener-policy", b"same-origin"),
                        (b"cross-origin-embedder-policy", b"require-corp"),
                        (b"x-content-type-options", b"nosniff"),
                    ],
                }
            await send(message)

        await self.app(scope, receive, with_headers)


def checked_origin(value):
    uri = urlsplit(value)
    if (
        uri.scheme not in {"https", "http"}
        or not uri.hostname
        or uri.username
        or uri.password
        or uri.path not in ("", "/")
        or uri.query
        or uri.fragment
        or uri.scheme == "http"
        and uri.hostname not in {"127.0.0.1", "localhost", "::1"}
    ):
        raise ValueError("Use a fixed HTTPS origin, or loopback HTTP for development")
    uri.port  # Reject an invalid port before starting the server.
    return value.rstrip("/")


class ProxyStream(StreamingResponse):
    def __init__(self, upstream):
        super().__init__(upstream.aiter_raw(), status_code=upstream.status_code)
        dropped = HOP | {"server", "date", "x-accel-redirect"}
        dropped.update(
            p.strip().lower() for p in upstream.headers.get("connection", "").split(",")
        )
        self.raw_headers = [
            (k, v) for k, v in upstream.headers.raw if k.decode().lower() not in dropped
        ]
        self.upstream = upstream

    async def __call__(self, scope, receive, send):
        try:
            async with asyncio.timeout(600):
                await super().__call__(scope, receive, send)
        finally:
            await self.upstream.aclose()


class WebFiles(StaticFiles):
    async def get_response(self, path, scope):
        try:
            response = await super().get_response(path, scope)
        except Exception as error:
            # StaticFiles validates containment and symlinks before serving.
            if getattr(error, "status_code", None) != 404 or Path(path).suffix:
                raise
            response = await super().get_response("index.html", scope)
        return response

    def file_response(self, full_path, stat_result, scope, status_code=200):
        with open(full_path, "rb") as source:
            etag = '"' + hashlib.file_digest(source, "sha256").hexdigest() + '"'
        request_headers = dict(scope.get("headers", []))
        validators = request_headers.get(b"if-none-match", b"").decode().split(",")
        headers = {"ETag": etag, "Cache-Control": "no-cache"}
        if any(value.strip().removeprefix("W/") in (etag, "*") for value in validators):
            return Response(status_code=304, headers=headers)
        return FileResponse(
            full_path, stat_result=stat_result, status_code=status_code, headers=headers
        )


def create_app(
    directory,
    api_upstream,
    *,
    origins,
    allowed_ai_origins=None,
    api_client=None,
    ai_client=None,
):
    api_upstream = checked_origin(api_upstream)
    origins = frozenset(checked_origin(value) for value in origins)
    if not origins:
        raise ValueError("At least one preview browser origin is required")
    owned_api, owned_ai = api_client is None, ai_client is None
    api_client = api_client or httpx.AsyncClient(
        trust_env=False,
        follow_redirects=False,
        timeout=httpx.Timeout(35, connect=10, read=90),
        limits=httpx.Limits(max_connections=16, max_keepalive_connections=8),
    )
    ai_client = ai_client or httpx.AsyncClient(
        trust_env=False,
        follow_redirects=False,
        timeout=httpx.Timeout(35, connect=10, read=180),
        limits=httpx.Limits(max_connections=8, max_keepalive_connections=4),
    )
    relay = AiRelay(
        allowed_ai_origins
        or (
            "https://api.openai.com",
            "https://api.deepseek.com",
            "https://www.loomex.lol",
            "https://loomex.lol",
        ),
        ai_client,
    )

    @asynccontextmanager
    async def lifespan(_):
        try:
            yield
        finally:
            if owned_api:
                await api_client.aclose()
            if owned_ai:
                await ai_client.aclose()

    def origin_allowed(request):
        origin = request.headers.get("origin")
        return (not origin or origin in origins) and request.headers.get(
            "sec-fetch-site"
        ) != "cross-site"

    async def api(request):
        if not origin_allowed(request):
            return JSONResponse({"code": "previewOriginDenied"}, 403)
        path = request.url.path.removeprefix("/api")
        if not path.startswith(("/v1/", "/powersync/")) or ".." in path.split("/"):
            return JSONResponse({"code": "previewRouteNotFound"}, 404)
        body = bytearray()
        try:
            async with asyncio.timeout(15):
                async for chunk in request.stream():
                    if len(body) + len(chunk) > LIMIT:
                        return JSONResponse({"code": "previewRequestTooLarge"}, 413)
                    body.extend(chunk)
        except TimeoutError:
            return JSONResponse({"code": "previewRequestTimeout"}, 408)
        headers = {
            k: v for k, v in request.headers.items() if k.lower() in REQUEST_HEADERS
        }
        if request.client:
            headers["X-Forwarded-For"] = request.client.host
        # A local preview has no NAS file mount. Never request X-Accel delivery.
        try:
            target = httpx.URL(api_upstream + path).copy_with(
                query=request.url.query.encode()
            )
            upstream = await api_client.send(
                api_client.build_request(
                    request.method, target, content=bytes(body), headers=headers
                ),
                stream=True,
            )
            if "x-accel-redirect" in upstream.headers:
                await upstream.aclose()
                return JSONResponse({"code": "unexpectedFileAcceleration"}, 502)
            return ProxyStream(upstream)
        except httpx.TimeoutException:
            return JSONResponse({"code": "applicationServiceTimeout"}, 504)
        except httpx.HTTPError:
            return JSONResponse({"code": "applicationServiceUnavailable"}, 502)

    async def ai(request):
        if (
            not origin_allowed(request)
            or request.headers.get("x-board-game-request") != "1"
        ):
            return JSONResponse({"code": "aiOriginDenied"}, 403)
        try:
            return await relay.forward(request)
        except AiRelayError as error:
            return JSONResponse(
                {"code": error.code, "message": error.message}, error.status
            )

    async def health(_):
        return JSONResponse({"status": "ok"})

    app = Starlette(
        routes=[
            Route("/healthz", health),
            Route("/api/ai/request", ai, methods=["GET", "POST"]),
            Route(
                "/api/{path:path}",
                api,
                methods=["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
            ),
            Mount(
                "/", app=WebFiles(directory=directory, html=True, follow_symlink=False)
            ),
        ],
        lifespan=lifespan,
        middleware=[Middleware(IsolationHeaders)],
    )
    return app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8083)
    parser.add_argument(
        "--host", choices=["127.0.0.1", "localhost", "::1"], default="127.0.0.1"
    )
    parser.add_argument("--directory", type=Path, default=ROOT / "build/web")
    parser.add_argument("--api-upstream", default="https://cznas.pp.ua:18281")
    parser.add_argument("--ssl-certfile", type=Path)
    parser.add_argument("--ssl-keyfile", type=Path)
    args = parser.parse_args()
    if bool(args.ssl_certfile) != bool(args.ssl_keyfile):
        parser.error("HTTPS requires both a certificate and a private key")
    scheme = "https" if args.ssl_certfile else "http"
    app = create_app(
        args.directory,
        args.api_upstream,
        origins=[
            f"{scheme}://127.0.0.1:{args.port}",
            f"{scheme}://localhost:{args.port}",
            f"{scheme}://[::1]:{args.port}",
        ],
    )
    import uvicorn

    print(
        f"Web preview: {scheme}://{args.host}:{args.port}; application API uses /api/"
    )
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        access_log=False,
        ssl_certfile=str(args.ssl_certfile) if args.ssl_certfile else None,
        ssl_keyfile=str(args.ssl_keyfile) if args.ssl_keyfile else None,
        timeout_keep_alive=5,
    )


if __name__ == "__main__":
    main()
