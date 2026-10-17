"""Same-origin DSM sign-in gateway. No NAS password or SID leaves this process.

Starlette owns HTTP/ASGI and HTTPX owns upstream TLS, pooling and deadlines.
DSM discovery/Auth v6/FileStation.Info follow the same protocol as app_identity.
Mounts are read-only; only authenticated own-comment snapshots can be uploaded
through the user's DSM session. There is no generic proxy or file-write API.
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
from urllib.parse import urlsplit, quote
from weakref import WeakValueDictionary

import httpx
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import Route
try:
    from .library import Library, LibraryError
    from .comments import Comments
    from .account_files import AccountFiles
except ImportError:  # Docker's /app module layout.
    from library import Library, LibraryError
    from comments import Comments
    from account_files import AccountFiles


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
    library_root: str = "/data/library"
    library_nas_path: str = "/friend/apps/board_game_agent/board-game-lib"
    comments_root: str = "/data/comments"
    comments_nas_path: str = "/friend/apps/board_game_agent_comments/public/v1"
    shared_folder: str = "friend"

    def __post_init__(self):
        object.__setattr__(self, "nas_origin", origin(self.nas_origin))
        object.__setattr__(self, "identity_origin", origin(self.identity_origin))
        object.__setattr__(self, "public_origin", origin(self.public_origin, allow_http=self.insecure_http))
        if min(self.max_sessions, self.idle_seconds, self.lifetime_seconds) <= 0:
            raise ValueError("Positive session limits are required")
        if (not self.shared_folder or len(self.shared_folder) > 240 or any(
                part in ("", ".", "..") or not re.fullmatch(r"[\w .-]+", part)
                for part in self.shared_folder.split("/"))):
            raise ValueError("A fixed account shared folder is required")
        if (not self.comments_nas_path.startswith("/") or any(
                part in ("", ".", "..") for part in self.comments_nas_path[1:].split("/"))
                or any(c in self.comments_nas_path for c in "\\\x00\r\n")):
            raise ValueError("A fixed NAS comments path is required")
        if (not self.library_nas_path.startswith("/") or any(
                part in ("", ".", "..") for part in self.library_nas_path[1:].split("/"))
                or any(c in self.library_nas_path for c in "\\\x00\r\n")):
            raise ValueError("A fixed NAS library path is required")

    @classmethod
    def from_env(cls):
        nas = os.environ["SYNOLOGY_ORIGIN"]
        return cls(nas, os.getenv("SYNOLOGY_IDENTITY_ORIGIN", nas),
                   os.environ["WEB_PUBLIC_ORIGIN"],
                   os.getenv("WEB_ALLOW_INSECURE_HTTP", "false").lower() == "true",
                   library_root=os.getenv("LIBRARY_ROOT", "/data/library"),
                   shared_folder=os.getenv("ACCOUNT_SHARED_FOLDER", "friend"),
                   comments_root=os.getenv("COMMENTS_ROOT", "/data/comments"),
                   comments_nas_path=os.getenv("COMMENTS_NAS_PATH", "/friend/apps/board_game_agent_comments/public/v1"),
                   library_nas_path=os.getenv("LIBRARY_NAS_PATH", "/friend/apps/board_game_agent/board-game-lib"))


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
        self.download_path: str | None = None

    @staticmethod
    def headers(session=None):
        # The client pool is shared by browser accounts. Explicitly override its
        # cookie jar on EVERY request; never install account credentials globally.
        headers = {"Accept": "application/json", "Cookie": ""}
        if session is not None:
            sid = secret(session.sid)
            # RFC 6265 cookie-octet, without quoting or cookie/header injection.
            if not re.fullmatch(r"[\x21\x23-\x2b\x2d-\x3a\x3c-\x5b\x5d-\x7e]+", sid):
                raise Failure("providerUnavailable")
            headers["Cookie"] = f"id={sid}"
            if session.token is not None:
                token = secret(session.token)
                if not token.isascii():
                    raise Failure("providerUnavailable")
                headers["X-SYNO-TOKEN"] = token
        return headers

    async def api(self, path, fields, *, session=None, file=None, raw_limit=None):
        if not isinstance(path, str) or not re.fullmatch(r"[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\.cgi", path):
            raise Failure("providerUnavailable")
        try:
            # DSM authenticates the request before parsing some POST APIs.
            # A body-only SID/token can return 119 even after successful login.
            # Use request-local Cookie + token header, keeping secrets out of URLs.
            async with self.client.stream("POST", f"{self.settings.nas_origin}/webapi/{path}",
                                          data=fields, headers=self.headers(session),
                                          **({"files": {"file": file}} if file else {}),
                                          follow_redirects=False) as response:
                if response.status_code == 429:
                    raise Failure("rateLimited", 429)
                if response.status_code != 200:
                    raise Failure("providerUnavailable")
                payload = bytearray()
                async for chunk in response.aiter_bytes():
                    payload.extend(chunk)
                    if len(payload) > (raw_limit or 256 * 1024):
                        raise Failure("providerUnavailable")
            value = json.loads(payload)
            if raw_limit is not None and not (isinstance(value, dict) and value.get("success") is False):
                return bytes(payload)
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
                    error = "storageQuota" if code in (415, 416) else "missing" if code == 408 else "accountDenied" if code in (105, 403, 404, 407, 411) else (
                        "sessionRejected" if code in (106, 107, 119, 150, 400) else "providerUnavailable")
                raise Failure(error, 507 if error == "storageQuota" else 404 if error == "missing" else 401 if error in ("invalidCredentials", "sessionRejected") else 403)
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

    async def file_api(self, session, api, method, fields, *, file=None, raw_limit=None):
        if (api, method) not in {("SYNO.FileStation.List", "getinfo"),
                                 ("SYNO.FileStation.List", "list"),
                                 ("SYNO.FileStation.Download", "download"),
                                 ("SYNO.FileStation.CreateFolder", "create"),
                                 ("SYNO.FileStation.Upload", "upload")}:
            raise Failure("accountDenied", 403)
        data = await self.api("entry.cgi", {"api": "SYNO.API.Info", "version": "1",
                                           "method": "query", "query": api})
        spec = data.get(api, {})
        if (type(spec.get("minVersion")) is not int or type(spec.get("maxVersion")) is not int
                or not spec["minVersion"] <= 2 <= spec["maxVersion"]):
            raise Failure("providerUnavailable")
        return await self.api(spec.get("path", ""), {"api": api, "version": "2", "method": method, **fields},
                              session=session, file=file, raw_limit=raw_limit)

    async def uid(self, session):
        data = await self.api(session.info_path, {"api": "SYNO.FileStation.Info", "version": "2", "method": "get"},
                              session=session)
        uid = data.get("uid")
        if type(uid) is not int or uid <= 0:
            raise Failure("sessionRejected", 401)
        return uid

    async def revoke(self, session):
        try:
            await self.api(session.auth_path, {"api": "SYNO.API.Auth", "version": "6", "method": "logout",
                                                "session": "FileStation"}, session=session)
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

    async def readable(self, session, logical):
        # Ask DSM to authorize this exact file with this user's SID. Only the
        # permission probe goes through FileStation; the real body is local.
        if not self.download_path:
            info = await self.api("entry.cgi", {"api": "SYNO.API.Info", "version": "1", "method": "query",
                                             "query": "SYNO.FileStation.Download"})
            spec = info.get("SYNO.FileStation.Download", {})
            path = spec.get("path")
            if (not isinstance(path, str) or not re.fullmatch(r"[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\.cgi", path)
                    or type(spec.get("minVersion")) is not int or type(spec.get("maxVersion")) is not int
                    or not spec["minVersion"] <= 2 <= spec["maxVersion"]):
                raise Failure("providerUnavailable")
            self.download_path = path
        fields = {"api": "SYNO.FileStation.Download", "version": "2", "method": "download", "mode": "download",
                  "path": json.dumps([self.settings.library_nas_path + "/" + logical])}
        try:
            async with self.client.stream("POST", f"{self.settings.nas_origin}/webapi/{self.download_path}", data=fields,
                                          headers={**self.headers(session), "Range": "bytes=0-0"}, follow_redirects=False) as response:
                if response.status_code not in (200, 206):
                    raise Failure("accountDenied", 403)
                if ("json" in response.headers.get("content-type", "")
                        and "content-disposition" not in response.headers):
                    payload = bytearray()
                    async for chunk in response.aiter_bytes():
                        if len(payload) + len(chunk) > 65536:
                            raise Failure("providerUnavailable")
                        payload.extend(chunk)
                    code = json.loads(payload).get("error", {}).get("code")
                    if code in (106, 107, 119, 150):
                        raise Failure("sessionRejected", 401)
                    raise Failure("accountDenied", 403)
                # Do not download a whole PDF if DSM ignores the Range header.
                async for chunk in response.aiter_bytes(chunk_size=1):
                    if chunk:
                        return
                raise Failure("providerUnavailable")
        except httpx.TimeoutException:
            raise Failure("timeout", 504) from None
        except httpx.HTTPError:
            raise Failure("network", 502) from None
        except (ValueError, AttributeError):
            raise Failure("providerUnavailable") from None


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
    library = Library(settings.library_root)
    comments = Comments(settings.comments_root, settings.comments_nas_path, Failure)
    comment_locks = WeakValueDictionary()
    account_files = AccountFiles(settings, Failure)
    sync_locks = WeakValueDictionary()
    library_lock = asyncio.Lock()
    sessions: dict[str, BrowserSession] = {}
    attempts: OrderedDict[str, list[float]] = OrderedDict()
    cookie = "bga_account_dev" if settings.insecure_http else "__Host-bga_account"

    def user(nas):
        return {"id": hashlib.sha256(f"synology-direct-v1|{settings.identity_origin}|{nas.uid}".encode()).hexdigest(),
                "displayName": nas.account, "uid": nas.uid}

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

    def guard(request, resource=False):
        # A browser cannot attach this custom header cross-origin without a
        # successful CORS preflight. This service deliberately offers no CORS.
        if ((not resource and request.headers.get("x-board-game-request") != "1")
                or request.headers.get("origin", settings.public_origin) != settings.public_origin
                or request.headers.get("sec-fetch-site") == "cross-site"):
            raise Failure("accountDenied", 403)

    def signed_in(request):
        guard(request, resource=True)
        _, state, _ = session(request)
        if state is None or state.nas is None:
            raise Failure("sessionRejected", 401)
        return state

    async def sync_files(request):
        guard(request)
        state = signed_in(request)
        nas, revision = state.nas, state.revision
        lane, action = request.path_params["lane"], request.path_params["action"]
        if request.headers.get("x-bga-account-uid") != str(nas.uid):
            raise Failure("sessionRejected", 401)
        relative = request.query_params.get("path", "")
        if lane not in ("private", "public") or action not in ("entries", "file"):
            raise Failure("missing", 404)
        writing = request.method == "POST"
        if writing and action != "file":
            raise Failure("accountDenied", 400)
        account_files.path(lane, relative, listing=action == "entries", writing=writing)
        def check():
            if state.nas is not nas or state.revision != revision:
                raise Failure("sessionRejected", 401)
        async def call(api, method, fields, **kwargs):
            check()
            value = await dsm.file_api(nas, api, method, fields, **kwargs)
            check()
            return value
        content = None
        if writing:
            limit(request, nas.account, bucket="sync-write", maximum=240)
            raw = bytearray()
            async for chunk in request.stream():
                raw.extend(chunk)
                if len(raw) > 50 * 1024 * 1024:
                    raise Failure("accountDenied", 413)
            try:
                content = json.loads(raw)["content"]
                account_files.validate(lane, relative, content, nas.uid)
            except (ValueError, TypeError, KeyError):
                raise Failure("accountDenied", 400) from None
        # Only uploads and first-use private-directory initialization serialize.
        lock = sync_locks.setdefault((nas.uid, lane), asyncio.Lock())
        async with asyncio.timeout(30), lock:
            check()
            if await dsm.uid(nas) != nas.uid:
                raise Failure("sessionRejected", 401)
            check()
            if writing:
                await account_files.write(call, lane, relative, content, nas.uid)
                value = {"saved": True}
            elif action == "entries":
                value = {"entries": await account_files.entries(call, lane, relative)}
            else:
                value = {"content": await account_files.read(call, lane, relative)}
            check()
        return answer(value)

    async def comment_entries(request):
        guard(request)
        try:
            values = await asyncio.to_thread(comments.entries, request.query_params.get("path", ""))
        except PermissionError:
            raise Failure("commentsUnreadable", 503) from None
        return answer({"entries": values})

    async def comment_file(request):
        guard(request)
        path = request.query_params.get("path", "")
        if request.method == "GET":
            try:
                return answer({"content": await asyncio.to_thread(comments.read, path)})
            except PermissionError:
                raise Failure("commentsUnreadable", 503) from None
        state = signed_in(request)
        nas, revision = state.nas, state.revision
        limit(request, nas.account, bucket="comments", maximum=60)
        raw = bytearray()
        async for chunk in request.stream():
            raw.extend(chunk)
            if len(raw) > 4 * 1024 * 1024:
                raise Failure("accountDenied", 413)
        try:
            value = json.loads(raw)
            content = value["content"]
            comments.validate(path, content, nas.uid)
        except (ValueError, TypeError, KeyError):
            raise Failure("accountDenied", 400) from None
        lock = comment_locks.setdefault(nas.uid, asyncio.Lock())
        async with asyncio.timeout(30), lock:
            if state.nas is not nas or state.revision != revision:
                raise Failure("sessionRejected", 401)
            if await dsm.uid(nas) != nas.uid:
                raise Failure("sessionRejected", 401)
            await comments.replace(dsm, nas, path, content)
            if state.nas is not nas or state.revision != revision:
                raise Failure("sessionRejected", 401)
        return answer({"saved": True})

    async def library_file(request):
        guard(request, resource=True)
        path = request.path_params["path"]
        # Anonymous readers may only access enabled, published manifest paths.
        # The raw Nginx directory remains inaccessible from the browser.
        async with library_lock:
            await asyncio.to_thread(library.resolve, path)
        stat = await asyncio.to_thread(lambda: library.resolve(path).stat())
        etag = f'"{stat.st_mtime_ns:x}-{stat.st_size:x}"'
        # Recheck the published allowlist before 304, including after removal.
        # Nginx drops upstream ETag during X-Accel-Redirect, so compare here
        # and re-attach it in the internal file location for 200/206/HEAD.
        if any(value.strip() in ("*", etag, "W/" + etag)
               for value in request.headers.get("if-none-match", "").split(",")):
            return Response(status_code=304, headers={"ETag": etag, "Cache-Control": "private, no-cache"})
        # Cache/security headers belong to the Nginx internal file location,
        # otherwise an internal redirect duplicates these response fields.
        return Response(headers={"X-Accel-Redirect": "/_library_files/" + quote(path, safe="/"),
                                 "ETag": etag})

    async def library_files(request):
        guard(request)
        directory = request.query_params.get("path", "assets")
        try:
            depth = min(10, max(0, int(request.query_params.get("depth", "6"))))
            maximum = min(1000, max(1, int(request.query_params.get("limit", "1000"))))
        except ValueError:
            raise Failure("providerUnavailable", 400) from None
        # A published game manifest grants visibility of its registered files.
        parts = directory.split("/")
        proof = "/".join(parts[:3]) + "/manifest.json" if len(parts) >= 3 and parts[:2] == ["assets", "games"] else "assets/catalog.json"
        async with library_lock:
            await asyncio.to_thread(library.resolve, proof)
            entries = await asyncio.to_thread(library.entries, directory, depth, maximum)
        return answer({"files": entries})

    async def library_versions(request):
        guard(request)
        async with library_lock:
            values = await asyncio.to_thread(library.versions)
        return answer({"files": values})

    def limit(request, account, *, bucket="login", maximum=10):
        now = time.monotonic()
        remote = request.headers.get("x-real-ip", request.client.host if request.client else "unknown")[:80]
        for key in (bucket + ":ip:" + remote, bucket + ":account:" + account.casefold()):
            times = [stamp for stamp in attempts.pop(key, []) if now - stamp < 60]
            if len(times) >= maximum:
                attempts[key] = times
                raise Failure("rateLimited", 429)
            attempts[key] = times + [now]
        while len(attempts) > 4096:
            attempts.popitem(last=False)

    async def config(request):
        guard(request)
        return answer({"version": 1, "nasOrigin": settings.nas_origin, "identityOrigin": settings.identity_origin,
                       "storageFolder": settings.shared_folder})

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

    async def library_error(request, error):
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
                             Route("/api/account/logout", logout, methods=["POST"]),
                             Route("/api/comments/entries", comment_entries),
                             Route("/api/comments/file", comment_file, methods=["GET", "POST"]),
                             Route("/api/sync/{lane:str}/{action:str}", sync_files, methods=["GET", "POST"]),
                             Route("/library/{path:path}", library_file, methods=["GET", "HEAD"]),
                             Route("/api/library/files", library_files),
                             Route("/api/library/versions", library_versions)],
                     exception_handlers={Failure: failure_handler, LibraryError: library_error,
                                         Exception: unexpected_handler}, lifespan=lifespan)
