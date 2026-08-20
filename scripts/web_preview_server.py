#!/usr/bin/env python3
"""Serve the Flutter Web build and proxy an OpenAI-compatible AI endpoint.

The provider used for local testing does not currently allow the Flutter Web
origin in its CORS preflight response.  This local-only server follows the
same preview-server pattern used by zheri: it serves ``build/web`` and maps
``/v1/*`` to the configured upstream URL on the same origin.

The proxy is intentionally bound to 127.0.0.1 by default.  It is a local
development aid, not a production API gateway.
"""

from __future__ import annotations

import argparse
import http.server
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from pathlib import Path


HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
}


class PreviewHandler(http.server.SimpleHTTPRequestHandler):
    """Static Flutter Web handler with an AI forwarding endpoint."""

    protocol_version = "HTTP/1.1"

    def send_head(self):  # noqa: ANN001 - mirrors stdlib handler API
        parsed = urllib.parse.urlsplit(self.path)
        decoded_path = urllib.parse.unquote(parsed.path)
        translated = Path(self.translate_path(decoded_path))
        if (
            decoded_path != "/"
            and not translated.exists()
            and Path(decoded_path).suffix == ""
        ):
            original_path = self.path
            self.path = "/index.html"
            try:
                return super().send_head()
            finally:
                self.path = original_path
        return super().send_head()

    def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        if self._is_ai_proxy_path():
            self._proxy_ai()
            return
        super().do_GET()

    def do_HEAD(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        if self._is_ai_proxy_path():
            self._proxy_ai(head_only=True)
            return
        super().do_HEAD()

    def do_OPTIONS(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        if self._is_ai_proxy_path():
            self.send_response(HTTPStatus.NO_CONTENT)
            self._write_cors_headers()
            self.end_headers()
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def do_POST(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        if self._is_ai_proxy_path():
            self._proxy_ai()
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def _is_ai_proxy_path(self) -> bool:
        parsed_path = urllib.parse.urlsplit(self.path).path
        return parsed_path == self.server.local_prefix or parsed_path.startswith(
            f"{self.server.local_prefix}/"
        )

    def _proxy_ai(self, *, head_only: bool = False) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        suffix = parsed.path[len(self.server.local_prefix) :]
        target = self.server.upstream_base._replace(
            path=_join_url_path(self.server.upstream_base.path, suffix),
            query=parsed.query,
        )
        target_url = urllib.parse.urlunsplit(target)

        content_length = int(self.headers.get("Content-Length", "0") or "0")
        request_body = self.rfile.read(content_length) if content_length else None
        forwarded_headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP_HEADERS
            and key.lower() not in {"host", "content-length", "origin"}
            and key.lower() in {"accept", "authorization", "content-type", "user-agent"}
        }
        forwarded_headers["Host"] = target.netloc

        request = urllib.request.Request(
            target_url,
            data=request_body,
            headers=forwarded_headers,
            method=self.command,
        )
        context = ssl.create_default_context()
        try:
            with urllib.request.urlopen(request, context=context, timeout=90) as response:
                body = response.read() if not head_only else b""
                self._write_proxy_response(
                    response.status,
                    response.headers.items(),
                    body,
                    head_only=head_only,
                )
        except urllib.error.HTTPError as error:
            body = error.read() if not head_only else b""
            self._write_proxy_response(
                error.code,
                error.headers.items(),
                body,
                head_only=head_only,
            )
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            self._send_json(
                HTTPStatus.BAD_GATEWAY,
                {"error": "AI proxy request failed.", "detail": str(error)},
            )

    def _write_proxy_response(
        self,
        status: int,
        headers: object,
        body: bytes,
        *,
        head_only: bool,
    ) -> None:
        self.send_response(status)
        self._write_cors_headers()
        content_length_sent = False
        for key, value in headers:  # type: ignore[union-attr]
            lower_key = key.lower()
            if lower_key in HOP_BY_HOP_HEADERS or lower_key == "content-length":
                continue
            self.send_header(key, value)
            if lower_key == "content-type":
                continue
        if not head_only:
            self.send_header("Content-Length", str(len(body)))
            content_length_sent = True
        if not content_length_sent and head_only:
            self.send_header("Content-Length", "0")
        self.end_headers()
        if body and not head_only:
            self.wfile.write(body)

    def _send_json(self, status: int, payload: dict[str, str]) -> None:
        body = _json_bytes(payload)
        self.send_response(status)
        self._write_cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _write_cors_headers(self) -> None:
        origin = self.headers.get("Origin")
        self.send_header("Access-Control-Allow-Origin", origin or "*")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Accept, Authorization, Content-Type, X-Request-ID",
        )
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Max-Age", "600")
        if origin:
            self.send_header("Vary", "Origin")

    def log_message(self, format: str, *args: object) -> None:
        # Do not log request headers or bodies; this keeps API keys out of the
        # preview terminal while retaining ordinary request diagnostics.
        sys.stderr.write(
            "%s - - [%s] %s\n"
            % (self.address_string(), self.log_date_time_string(), format % args)
        )


class PreviewServer(http.server.ThreadingHTTPServer):
    """HTTP server carrying immutable proxy configuration."""

    daemon_threads = True

    def __init__(self, address, handler, *, local_prefix, upstream_base):
        super().__init__(address, handler)
        self.local_prefix = local_prefix
        self.upstream_base = upstream_base


def _join_url_path(base_path: str, suffix: str) -> str:
    left = "/" + base_path.strip("/")
    right = "/" + suffix.strip("/") if suffix.strip("/") else ""
    return (left + right) or "/"


def _json_bytes(payload: dict[str, str]) -> bytes:
    import json

    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def _normalize_prefix(value: str) -> str:
    normalized = "/" + value.strip().strip("/")
    return normalized if normalized != "/" else "/v1"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parents[1] / "build" / "web")
    parser.add_argument("--upstream", required=True, help="OpenAI-compatible base URL, e.g. https://provider.example/v1")
    parser.add_argument("--local-prefix", default="/v1")
    args = parser.parse_args()

    if not args.directory.is_dir():
        raise SystemExit(f"Web build directory does not exist: {args.directory}")

    upstream = urllib.parse.urlsplit(args.upstream.rstrip("/") + "/")
    if upstream.scheme not in {"http", "https"} or not upstream.netloc:
        raise SystemExit("--upstream must be an HTTP or HTTPS URL")

    handler = lambda *handler_args, **handler_kwargs: PreviewHandler(  # noqa: E731
        *handler_args,
        directory=str(args.directory),
        **handler_kwargs,
    )
    server = PreviewServer(
        (args.host, args.port),
        handler,
        local_prefix=_normalize_prefix(args.local_prefix),
        upstream_base=upstream,
    )
    print(f"Serving {args.directory} at http://{args.host}:{args.port}/")
    print(f"AI proxy: {server.local_prefix}/* -> {args.upstream.rstrip('/')}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopping Web preview server.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
