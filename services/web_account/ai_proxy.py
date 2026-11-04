"""Bounded OpenAI-compatible HTTP relay; no model protocol or API-key storage.

HTTPX owns TLS/streaming and Starlette owns disconnect handling. Only explicitly
configured HTTPS origins and the app's existing model/chat/Responses routes run.
"""
import asyncio
import re
import tempfile
import time
from urllib.parse import urlsplit

import httpx
import ijson
from starlette.responses import Response, StreamingResponse


class AiRelayError(Exception):
    def __init__(self, code, message, status=502):
        self.code, self.message, self.status = code, message, status


class _RelayResponse(StreamingResponse):
    def __init__(self, *args, cleanup, **kwargs):
        super().__init__(*args, **kwargs)
        self.cleanup = cleanup

    async def __call__(self, scope, receive, send):
        try:
            await super().__call__(scope, receive, send)
        finally:
            await self.cleanup()


class AiRelay:
    request_limit = 16 * 1024 * 1024
    # One worker owns these counters. Admission never awaits or queues bodies.
    # All active requests share one full-size upload, rather than eight copies.
    request_bytes_budget = 16 * 1024 * 1024
    max_inflight = 8
    json_structure_limit = 65536
    json_depth_limit = 64
    response_limit = 64 * 1024 * 1024
    total_seconds = 180
    forwarded_headers = {"authorization", "api-key", "x-api-key", "content-type",
                         "openai-beta", "openai-organization", "openai-project", "idempotency-key", "accept"}

    def __init__(self, allowed_origins, client):
        self.allowed_origins, self.client = frozenset(allowed_origins), client
        self.inflight = 0
        self.reserved_request_bytes = 0

    def _validate_json(self, body):
        # Validate events, not a decoded document/tree. Only one scalar and a
        # bounded parser buffer are materialized, even for large PDF strings.
        # Pin ijson/YAJL in the runtime lock; do not implement a second parser.
        depth = 0
        try:
            for count, (event, _) in enumerate(ijson.basic_parse(body), 1):
                if count == 1 and event != 'start_map':
                    raise ValueError()
                if event in ('start_map', 'start_array'):
                    depth += 1
                elif event in ('end_map', 'end_array'):
                    depth -= 1
                if count > self.json_structure_limit or depth > self.json_depth_limit:
                    raise AiRelayError("aiRequestTooComplex", "AI 请求结构过于复杂，请减少历史或附件。", 413)
        except (ijson.JSONError, ValueError, TypeError, UnicodeError):
            raise AiRelayError("aiInvalidRequest", "AI 请求格式不正确。", 400) from None

    @staticmethod
    async def _upload(body):
        try:
            while chunk := body.read(64 * 1024):
                yield chunk
        finally:
            body.close()

    def target(self, value, method):
        try:
            if not isinstance(value, str) or len(value) > 2048:
                raise ValueError()
            parsed = urlsplit(value)
            if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
                    or parsed.query or parsed.fragment or "\\" in value or re.search(r"[\x00-\x20\x7f]", value)):
                raise ValueError()
            port = parsed.port
            site = f"https://{parsed.hostname.lower()}" + (f":{port}" if port not in (None, 443) else "")
            if site not in self.allowed_origins:
                raise AiRelayError("aiTargetDenied", "这个 AI 地址尚未加入服务器允许列表，请检查 Docker 的 AI_ALLOWED_ORIGINS。", 403)
            path = parsed.path
            if ("%" in path or "//" in path or any(part in (".", "..") for part in path.split("/"))
                    or not re.fullmatch(r"/(?:[a-zA-Z0-9_.~-]+/)*(?:models|chat/completions|responses(?:/compact)?)", path)
                    or method != ("GET" if path.endswith("/models") else "POST")):
                raise ValueError()
            return value
        except (ValueError, TypeError):
            raise AiRelayError("aiInvalidTarget", "AI 请求地址或方法不受支持。", 400) from None

    async def forward(self, request):
        target = self.target(request.headers.get("x-bga-ai-target"), request.method)
        headers = {key: value for key, value in request.headers.items() if key.lower() in self.forwarded_headers}
        keys = [headers.get(name) for name in ("authorization", "api-key", "x-api-key") if headers.get(name)]
        if not keys or any(len(value) > 8192 or re.search(r"[^\x20-\x7e]", value) for value in keys):
            raise AiRelayError("aiKeyRequired", "请填写有效的 AI 接口密钥。", 401)
        content_length = request.headers.get("content-length")
        if content_length is not None:
            if not re.fullmatch(r"[0-9]{1,10}", content_length):
                raise AiRelayError("aiInvalidRequest", "AI 请求格式不正确。", 400)
            content_length = int(content_length)
            if content_length > self.request_limit:
                raise AiRelayError("aiRequestTooLarge", "AI 请求内容过大。", 413)
        # Chunked uploads reserve their maximum up front, so competing uploads
        # cannot deadlock while waiting for memory or exceed the combined cap.
        reservation = (content_length if content_length is not None else self.request_limit) if request.method == "POST" else 0
        if self.inflight >= self.max_inflight or self.reserved_request_bytes + reservation > self.request_bytes_budget:
            raise AiRelayError("aiBusy", "AI 请求较多，请稍后重试。", 429)
        self.inflight += 1
        self.reserved_request_bytes += reservation
        upstream = None
        body = None
        closed = False

        async def cleanup():
            nonlocal closed
            if closed:
                return
            closed = True
            try:
                if upstream is not None:
                    await upstream.aclose()
            finally:
                try:
                    if body is not None:
                        body.close()
                finally:
                    self.inflight -= 1
                    self.reserved_request_bytes -= reservation

        deadline = time.monotonic() + self.total_seconds
        try:
            # Production /tmp is a bounded tmpfs. Anonymous files avoid keeping
            # a second, growable copy on Python's heap; no body survives close.
            body = tempfile.TemporaryFile(mode="w+b")
            body_size = 0
            async with asyncio.timeout_at(deadline):
                async for chunk in request.stream():
                    body_size += len(chunk)
                    if body_size > self.request_limit:
                        raise AiRelayError("aiRequestTooLarge", "AI 请求内容过大。", 413)
                    if (request.method != "POST" and chunk or
                            content_length is not None and body_size > content_length):
                        raise AiRelayError("aiInvalidRequest", "AI 请求格式不正确。", 400)
                    body.write(chunk)
                if content_length is not None and body_size != content_length:
                    raise AiRelayError("aiInvalidRequest", "AI 请求格式不正确。", 400)
                body.seek(0)
                if request.method == "POST":
                    if request.headers.get("content-type", "").split(";")[0] != "application/json":
                        raise AiRelayError("aiInvalidRequest", "AI 请求格式不正确。", 400) from None
                    self._validate_json(body)
                    body.seek(0)
                # Never forward browser/DSM cookies, tokens or proxy identity.
                headers["cookie"] = ""
                headers["accept-encoding"] = "identity"
                headers["content-length"] = str(body_size)
                upstream = await self.client.send(self.client.build_request(request.method, target,
                    headers=headers, content=self._upload(body)), stream=True, follow_redirects=False)
            if 300 <= upstream.status_code < 400:
                raise AiRelayError("aiRedirectDenied", "AI 接口返回了重定向，请填写最终接口地址。")
            media = upstream.headers.get("content-type", "").split(";")[0].lower()
            if media not in ("application/json", "text/event-stream"):
                raise AiRelayError("aiInvalidResponse", "AI 接口未返回有效的模型或问答数据。")

            response_headers = {"Cache-Control": "no-store", "X-Accel-Buffering": "no",
                                "X-Content-Type-Options": "nosniff"}
            for name in ("retry-after", "x-request-id"):
                if name in upstream.headers:
                    response_headers[name] = upstream.headers[name]
            if upstream.status_code >= 400:
                error_body = bytearray()
                async with asyncio.timeout_at(deadline):
                    async for chunk in upstream.aiter_bytes():
                        error_body.extend(chunk)
                        if len(error_body) > 64 * 1024:
                            raise AiRelayError("aiInvalidResponse", "AI 接口错误响应过大。")
                raw = bytes(error_body)
                for value in keys:
                    for sensitive in (value, value[7:] if value.lower().startswith("bearer ") else value):
                        if sensitive:
                            raw = raw.replace(sensitive.encode(), b"[redacted]")
                await cleanup()
                return Response(raw, status_code=upstream.status_code, media_type=media, headers=response_headers)

            async def chunks():
                count = 0
                try:
                    async with asyncio.timeout_at(deadline):
                        async for chunk in upstream.aiter_bytes():
                            count += len(chunk)
                            if count > self.response_limit:
                                raise AiRelayError("aiResponseTooLarge", "AI 响应过大。")
                            yield chunk
                except (httpx.HTTPError, TimeoutError):
                    # Headers may already have been sent. Close an incomplete
                    # stream; never fabricate a successful terminal event.
                    raise AiRelayError("aiStreamInterrupted", "AI 响应中断，请重试。") from None
                finally:
                    await cleanup()
            return _RelayResponse(chunks(), status_code=upstream.status_code,
                media_type=media, headers=response_headers, cleanup=cleanup)
        except BaseException as error:
            await cleanup()
            if isinstance(error, (httpx.TimeoutException, TimeoutError)):
                raise AiRelayError("aiTimeout", "AI 接口响应超时，请重试。", 504) from None
            if isinstance(error, httpx.HTTPError):
                raise AiRelayError("aiNetwork", "服务器无法连接 AI 接口，请检查接口地址和网络。") from None
            raise
