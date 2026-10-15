"""Same-origin DSM sign-in gateway. No NAS password or SID leaves this process.

Starlette owns HTTP/ASGI and HTTPX owns upstream TLS, pooling and deadlines.
DSM discovery/Auth v6/FileStation.Info follow the same protocol as app_identity.
This service intentionally has no filesystem, generic proxy or file-write API.
"""
from __future__ import annotations

import asyncio
from collections import OrderedDict
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
import hashlib
import json
import os
import re
import secrets
import ssl
import time
from urllib.parse import urlsplit

import httpx
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route


class Failure(Exception):
    def __init__(self, code: str, status: int = 503):
        self.code, self.status = code, status


def origin(value: str, *, allow_http: bool = False) -> str:
    parsed = urlsplit(value)
    if (parsed.scheme not in ({"https", "http"} if allow_http else {"https"})
            or not parsed.hostname or parsed.username or parsed.password
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise ValueError("A fixed origin without credentials or path is required")
    # Validate port and use the same normalized origin used by Dart Uri.origin.
    port = parsed.port
    host = parsed.hostname.lower()
    if ":" in host:
        host = f"[{host}]"
    suffix = "" if port in (None, 443 if parsed.scheme == "https" else 80) else f":{port}"
    return f"{parsed.scheme}://{host}{suffix}"


@dataclass(frozen=True)
class Settings:
    nas_origin: str
    identity_origin: str
    public_origin: str
    insecure_http: bool = False
    max_sessions: int = 1024
    idle_seconds: int = 1800
    lifetime_seconds: int = 28800

    def __post_init__(self):
        object.__setattr__(self, "nas_origin", origin(self.nas_origin))
        object.__setattr__(self, "identity_origin", origin(self.identity_origin))
        object.__setattr__(self, "public_origin", origin(self.public_origin, allow_http=self.insecure_http))
        if min(self.max_sessions, self.idle_seconds, self.lifetime_seconds) <= 0:
            raise ValueError("Positive session limits are required")

    @classmethod
    def from_env(cls):
        nas = os.environ["SYNOLOGY_ORIGIN"]
        return cls(nas, os.getenv("SYNOLOGY_IDENTITY_ORIGIN", nas),
                   os.environ["WEB_PUBLIC_ORIGIN"],
                   os.getenv("WEB_ALLOW_INSECURE_HTTP", "false").lower() == "true")


@dataclass
class NasSession:
    sid: str = field(repr=False)
    token: str | None = field(repr=False)
    auth_path: str
    info_path: str
    account: str
    uid: int


def secret(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 4096 or re.search(r"[\x00-\x20\x7f]", value):
        raise Failure("providerUnavailable")
    return value


class Dsm:
    def __init__(self, settings: Settings, client: httpx.AsyncClient):
        self.settings, self.client = settings, client
        self.paths: tuple[str, str] | None = None

    async def api(self, path, fields):
        if not re.fullmatch(r"[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\.cgi", path):
            raise Failure("providerUnavailable")
        try:
            # POST keeps SID, OTP and password out of URLs and access logs.
            async with self.client.stream("POST", f"{self.settings.nas_origin}/webapi/{path}",
                                          data=fields, headers={"Accept": "application/json", "Cookie": ""},
                                          follow_redirects=False) as response:
                if response.status_code == 429:
                    raise Failure("rateLimited", 429)
                if response.status_code != 200:
                    raise Failure("providerUnavailable")
                payload = bytearray()
                async for chunk in response.aiter_bytes():
                    payload.extend(chunk)
                    if len(payload) > 65536:
                        raise Failure("providerUnavailable")
            value = json.loads(payload)
            if not isinstance(value, dict) or type(value.get("success")) is not bool:
                raise Failure("providerUnavailable")
            if not value["success"]:
                code = value.get("error", {}).get("code")
                if fields.get("method") == "login":
                    error = {400: "invalidCredentials", 401: "accountDenied", 402: "accountDenied",
                             403: "otpRequired", 406: "otpRequired", 404: "invalidOtp",
                             407: "rateLimited", 408: "passwordChangeRequired",
                             409: "passwordChangeRequired", 410: "passwordChangeRequired"}.get(code, "providerUnavailable")
                else:
                    error = "accountDenied" if code == 105 else (
                        "sessionRejected" if code in (106, 107, 119, 150, 400) else "providerUnavailable")
                raise Failure(error, 401 if error in ("invalidCredentials", "sessionRejected") else 403)
            data = value.get("data", {})
            if not isinstance(data, dict):
                raise Failure("providerUnavailable")
            return data
        except httpx.TimeoutException:
            raise Failure("timeout", 504) from None
        except httpx.HTTPError:
            raise Failure("network", 502) from None
        except (ValueError, TypeError, AttributeError):
            raise Failure("providerUnavailable") from None

    async def discover(self):
        if self.paths:
            return self.paths
        data = await self.api("entry.cgi", {"api": "SYNO.API.Info", "version": "1", "method": "query",
                                             "query": "SYNO.API.Auth,SYNO.FileStation.Info"})
        paths = []
        for name, version in (("SYNO.API.Auth", 6), ("SYNO.FileStation.Info", 2)):
            spec = data.get(name)
            if (not isinstance(spec, dict) or type(spec.get("minVersion")) is not int
                    or type(spec.get("maxVersion")) is not int
                    or not spec["minVersion"] <= version <= spec["maxVersion"]
                    or not isinstance(spec.get("path"), str)
                    or not re.fullmatch(r"[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\.cgi", spec["path"])):
                raise Failure("providerUnavailable")
            paths.append(spec["path"])
        self.paths = tuple(paths)
        return self.paths

    async def uid(self, session):
        data = await self.api(session.info_path, {"api": "SYNO.FileStation.Info", "version": "2", "method": "get",
                                                 "_sid": session.sid, **({"SynoToken": session.token} if session.token else {})})
        uid = data.get("uid")
        if type(uid) is not int or uid <= 0:
            raise Failure("sessionRejected", 401)
        return uid

    async def revoke(self, session):
        try:
            await self.api(session.auth_path, {"api": "SYNO.API.Auth", "version": "6", "method": "logout",
                                                "session": "FileStation", "_sid": session.sid,
                                                **({"SynoToken": session.token} if session.token else {})})
        except Failure as failure:
            if failure.code != "sessionRejected":
                raise

    async def login(self, account, password, otp):
        auth, info = await self.discover()
        data = await self.api(auth, {"api": "SYNO.API.Auth", "version": "6", "method": "login",
                                    "session": "FileStation", "format": "sid", "enable_syno_token": "yes",
                                    "account": account, "passwd": password, **({"otp_code": otp} if otp else {})})
        candidate = NasSession(secret(data.get("sid")), secret(data["synotoken"]) if data.get("synotoken") else None,
                               auth, info, account, 0)
        try:
            candidate.uid = await self.uid(candidate)
            return candidate
        except BaseException:
            try:
                await asyncio.wait_for(self.revoke(candidate), 2)
            except (Failure, TimeoutError):
                pass
            raise


@dataclass
class BrowserSession:
    born: float
    touched: float
    revision: int = 0
    nas: NasSession | None = field(default=None, repr=False)
    busy: bool = False


def create_app(settings: Settings | None = None, upstream: httpx.AsyncClient | None = None):
    settings = settings or Settings.from_env()
    owned = upstream is None
    upstream = upstream or httpx.AsyncClient(timeout=8, trust_env=False,
                                              verify=ssl.create_default_context(cafile=os.getenv("DSM_CA_FILE")),
                                              limits=httpx.Limits(max_connections=32, max_keepalive_connections=16))
    dsm = Dsm(settings, upstream)
    sessions: dict[str, BrowserSession] = {}
    attempts: OrderedDict[str, list[float]] = OrderedDict()
    cookie = "bga_account_dev" if settings.insecure_http else "__Host-bga_account"

    def user(nas):
        return {"id": hashlib.sha256(f"synology-direct-v1|{settings.identity_origin}|{nas.uid}".encode()).hexdigest(),
                "displayName": nas.account}

    async def revoke_quiet(nas):
        if nas:
            try:
                await asyncio.wait_for(dsm.revoke(nas), 2)
            except (Failure, TimeoutError):
                pass

    def session(request, create=False):
        now = time.monotonic()
        for key, state in list(sessions.items()):
            if now - state.born >= settings.lifetime_seconds or now - state.touched >= settings.idle_seconds:
                state.revision += 1
                state.nas = None
                del sessions[key]
        key = request.cookies.get(cookie, "")
        state = sessions.get(key)
        if state:
            state.touched = now
            return key, state, False
        if not create:
            return None, None, False
        if len(sessions) >= settings.max_sessions:
            raise Failure("rateLimited", 429)
        key = secrets.token_urlsafe(32)
        state = sessions[key] = BrowserSession(now, now)
        return key, state, True

    def answer(data, *, key=None, new=False, status=200):
        response = JSONResponse(data, status_code=status)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        if new:
            response.set_cookie(cookie, key, max_age=settings.lifetime_seconds, httponly=True,
                                secure=not settings.insecure_http, samesite="strict", path="/")
        return response

    def guard(request):
        # A browser cannot attach this custom header cross-origin without a
        # successful CORS preflight. This service deliberately offers no CORS.
        if (request.headers.get("x-board-game-request") != "1"
                or request.headers.get("origin", settings.public_origin) != settings.public_origin
                or request.headers.get("sec-fetch-site") == "cross-site"):
            raise Failure("accountDenied", 403)

    def limit(request, account):
        now = time.monotonic()
        remote = request.headers.get("x-real-ip", request.client.host if request.client else "unknown")[:80]
        for key in ("ip:" + remote, "account:" + account.casefold()):
            times = [stamp for stamp in attempts.pop(key, []) if now - stamp < 60]
            if len(times) >= 10:
                attempts[key] = times
                raise Failure("rateLimited", 429)
            attempts[key] = times + [now]
        while len(attempts) > 4096:
            attempts.popitem(last=False)

    async def config(request):
        guard(request)
        return answer({"version": 1, "nasOrigin": settings.nas_origin, "identityOrigin": settings.identity_origin})

    async def current(request):
        guard(request)
        key, state, new = session(request, create=True)
        nas, revision = state.nas, state.revision
        if nas:
            try:
                async with asyncio.timeout(12):
                    verified_uid = await dsm.uid(nas)
                if verified_uid != nas.uid:
                    raise Failure("sessionRejected", 401)
            except Failure as failure:
                if failure.code in ("sessionRejected", "accountDenied"):
                    if state.revision == revision:
                        state.nas = None
                        state.revision += 1
                    if failure.code == "accountDenied":
                        raise
                else:
                    raise
        return answer({"user": user(state.nas) if state.nas and state.revision == revision else None}, key=key, new=new)

    async def login(request):
        guard(request)
        _, state, _ = session(request)
        if state is None:
            raise Failure("sessionRejected", 401)
        if state.busy or state.nas:
            raise Failure("sessionRejected", 409)
        raw = bytearray()
        async for chunk in request.stream():
            raw.extend(chunk)
            if len(raw) > 8192:
                raise Failure("invalidCredentials", 400)
        if request.headers.get("content-type", "").split(";")[0] != "application/json":
            raise Failure("invalidCredentials", 400)
        try:
            body = json.loads(raw)
        except (ValueError, UnicodeError):
            raise Failure("invalidCredentials", 400) from None
        if not isinstance(body, dict) or set(body) - {"account", "password", "otp"}:
            raise Failure("invalidCredentials", 400)
        account, password, otp = body.get("account"), body.get("password"), body.get("otp")
        if (not isinstance(account, str) or not 1 <= len(account.strip()) <= 200
                or re.search(r"[\x00-\x1f\x7f]", account)
                or not isinstance(password, str) or not 1 <= len(password) <= 1024
                or (otp is not None and (not isinstance(otp, str) or not re.fullmatch(r"\d{6,8}", otp)))):
            raise Failure("invalidCredentials", 400)
        limit(request, account.strip())
        state.revision += 1
        revision = state.revision
        state.busy = True
        candidate = None
        try:
            async with asyncio.timeout(18):
                candidate = await dsm.login(account.strip(), password, otp)
            if state.revision != revision:
                await revoke_quiet(candidate)
                raise Failure("cancelled", 409)
            # Only a verified UID can become a browser identity. No SID/token
            # is serialized into a cookie or response.
            state.nas = candidate
            return answer({"user": user(candidate)})
        finally:
            state.busy = False

    async def logout(request):
        guard(request)
        _, state, _ = session(request)
        if state:
            nas = state.nas
            state.revision += 1
            state.nas = None  # Local invalidation precedes remote revocation.
            await revoke_quiet(nas)
        return answer({"user": None})

    async def failure_handler(request, error):
        return answer({"error": error.code}, status=error.status)

    async def unexpected_handler(request, error):
        # Provider errors, request bodies and upstream URLs never enter replies.
        return answer({"error": "timeout" if isinstance(error, TimeoutError) else "providerUnavailable"}, status=503)

    @asynccontextmanager
    async def lifespan(app):
        yield
        for state in sessions.values():
            state.revision += 1
        await asyncio.gather(*(revoke_quiet(state.nas) for state in sessions.values()))
        if owned:
            await upstream.aclose()

    return Starlette(routes=[Route("/api/account/config", config), Route("/api/account/session", current),
                             Route("/api/account/login", login, methods=["POST"]),
                             Route("/api/account/logout", logout, methods=["POST"])],
                     exception_handlers={Failure: failure_handler, Exception: unexpected_handler}, lifespan=lifespan)
