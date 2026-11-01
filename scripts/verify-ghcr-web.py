"""Smoke-test actual Web images against isolated fixtures, never the user's NAS."""
import argparse
import hashlib
import http.client
import json
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from uuid import uuid4

MOCK = '''from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json,time
PDF=b"%PDF-fixture"+bytes(range(256))*32
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_HEAD(self): self.do_GET()
 def do_GET(self):
  if self.headers.get("Upgrade","").lower()=="websocket":
   self.send_response(101); self.send_header("Upgrade","websocket"); self.send_header("Connection","Upgrade"); self.end_headers(); return
  if self.path.endswith("/stream"):
   self.send_response(200); self.send_header("Content-Type","text/event-stream"); self.end_headers()
   self.wfile.write(b"data: first\\n\\n"); self.wfile.flush(); time.sleep(1)
   self.wfile.write(b"data: [DONE]\\n\\n"); return
  data=json.dumps({"path":self.path,"cookie":self.headers.get("Cookie"),"csrf":self.headers.get("X-CSRF-Token"),"origin":self.headers.get("Origin")}).encode()
  status=200
  if self.path.endswith("/pdf"):
   data=PDF
   if self.headers.get("Range")=="bytes=100-199": status=206; data=PDF[100:200]
  self.send_response(status); self.send_header("Content-Type","application/pdf" if self.path.endswith("/pdf") else "application/json")
  self.send_header("Content-Length",str(len(data))); self.send_header("ETag",'"fixture"')
  if status==206:self.send_header("Content-Range",f"bytes 100-199/{len(PDF)}")
  self.send_header("Set-Cookie","__Host-app-session-board_game_agent=fixture; Path=/; HttpOnly; Secure; SameSite=Strict")
  self.end_headers()
  if self.command!="HEAD":self.wfile.write(data)
ThreadingHTTPServer(("0.0.0.0",8000),Handler).serve_forever()
'''


def run(*args):
    return subprocess.run(["docker", *args], check=True, text=True, capture_output=True, timeout=120).stdout.strip()


def verify(web_image, ai_image, output, ai_input_digest=None, expected_version=None, previous_web_image=None):
    prefix = "bga-web-check-" + uuid4().hex[:10]
    created = []
    checks = []
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def check(label, condition):
        if not condition:
            raise AssertionError(label)
        checks.append(label)

    def request(path, **kwargs):
        try:
            return opener.open(urllib.request.Request(base + path, **kwargs), timeout=10)
        except urllib.error.HTTPError as error:
            return error

    run("network", "create", prefix)
    try:
        with tempfile.TemporaryDirectory(prefix="bga-web-fixtures-") as temporary:
            folder = Path(temporary)
            folder.chmod(0o755)
            fixture = folder / "api.py"
            fixture.write_text(MOCK, encoding="utf-8")
            fixture.chmod(0o644)
            for name, options, image, command in [
                ("api", ["--network-alias", "mock-api", "--mount", f"type=bind,source={fixture},target=/fixture.py,readonly", "--entrypoint", "python"], ai_image, ["/fixture.py"]),
                ("ai", ["--network-alias", "web-ai", "-e", "WEB_PUBLIC_ORIGIN=https://games.example.test"], ai_image, []),
                ("web", ["-p", "127.0.0.1::8080", "-e", "APP_SERVICE_UPSTREAM=http://mock-api:8000", "--read-only", "--tmpfs", "/tmp:rw,nosuid,nodev,size=64m"], web_image, []),
            ]:
                container = prefix + "-" + name
                run("run", "-d", "--name", container, "--network", prefix, "--pull", "never", *options, image, *command)
                created.append(container)
            info = json.loads(run("inspect", created[-1]))[0]
            ports = info.get("NetworkSettings", {}).get("Ports", {}).get("8080/tcp")
            if not ports:
                raise RuntimeError("Web container exited before exposing port 8080; inspect the validation failure report")
            port = ports[0]["HostPort"]
            base = "http://127.0.0.1:" + port
            deadline = time.monotonic() + 60
            while True:
                try:
                    with request("/healthz") as response:
                        if response.status == 200:
                            break
                except OSError:
                    pass
                if time.monotonic() >= deadline:
                    raise TimeoutError("Web did not start")
                time.sleep(.5)
            for path in ["/", "/main.dart.js", "/powersync/sqlite3.wasm", "/powersync/powersync_db.worker.js", "/settings/ai",
                         "/canvaskit/canvaskit.wasm", "/assets/assets/fonts/NotoSansSC-Variable.ttf",
                         "/assets/packages/pdfrx/assets/pdfium.wasm", "/assets/AssetManifest.bin"]:
                with request(path) as response:
                    check("static " + path, response.status == 200 and bool(response.read(16)))
                    check("isolation " + path, response.headers.get("Cross-Origin-Opener-Policy") == "same-origin" and response.headers.get("Cross-Origin-Embedder-Policy") == "require-corp")
                    if path.endswith(".wasm"):
                        check("WASM MIME", response.headers.get_content_type() == "application/wasm")
            if expected_version is not None:
                version, build = expected_version.split("+", 1)
                with request("/version.json") as response:
                    installed = json.load(response)
                    check("compiled application version", installed.get("version") == version
                          and str(installed.get("build_number")) == build)
            with request("/version.json") as response:
                body = response.read()
                etag = response.headers.get("ETag")
                modified = response.headers.get("Last-Modified")
                check("content-based static ETag", etag == '"sha256:' + hashlib.sha256(body).hexdigest() + '"')
            for value in (etag, "W/" + etag, '"other", ' + etag, "*"):
                with request("/version.json", headers={"If-None-Match": value}) as response:
                    check("static ETag revalidation " + value, response.status == 304 and response.headers.get("ETag") == etag)
            with request("/version.json", headers={"If-None-Match": '"sha256:' + "0" * 64 + '"',
                         "If-Modified-Since": modified}) as response:
                check("stale static validators do not hide updates", response.status == 200 and response.read() == body)
            with request("/VERSION.JSON", headers={"If-None-Match": etag}) as response:
                check("static cache lookup keeps URL case", response.status == 404)
            if previous_web_image is not None:
                previous = run("run", "--rm", "--entrypoint", "/bin/sh", previous_web_image, "-c",
                    "sha256sum /usr/share/nginx/html/version.json; wc -c < /usr/share/nginx/html/version.json").splitlines()
                previous_etag = '"sha256:' + previous[0].split()[0] + '"'
                check("update fixture keeps version file size", int(previous[1].strip()) == len(body))
                with request("/version.json", headers={"If-None-Match": previous_etag,
                             "If-Modified-Since": modified}) as response:
                    check("same-size version update invalidates old cache", response.status == 200
                          and response.read() == body and previous_etag != etag)
            with request("/missing-file.js") as response:
                check("missing assets stay 404", response.status == 404)
            with request("/_catalog_files/aa/" + "a" * 64) as response:
                check("catalog files cannot bypass SQL through an internal path", response.status == 404)
            with request("/api/v1/apps/board_game_agent/probe", headers={"Origin": "https://games.example.test", "Cookie": "fixture=1", "X-CSRF-Token": "fixture-csrf"}) as response:
                body = json.load(response)
                check("new API path", body["path"] == "/v1/apps/board_game_agent/probe")
                check("cookie/CSRF/origin preserved", body["cookie"] == "fixture=1" and body["csrf"] == "fixture-csrf" and body["origin"] == "https://games.example.test")
                check("secure HttpOnly cookie preserved", "HttpOnly" in response.headers.get("Set-Cookie", "") and "Secure" in response.headers.get("Set-Cookie", ""))
            with request("/api/powersync/probe") as response:
                check("PowerSync same-origin path", json.load(response)["path"] == "/powersync/probe")
            with request("/api/v1/apps/board_game_agent/pdf", headers={"Range": "bytes=100-199"}) as response:
                check("PDF range bytes", response.status == 206 and len(response.read()) == 100 and response.headers.get("ETag") == '"fixture"')
                check("proxy ETag is not duplicated", response.headers.get_all("ETag") == ['"fixture"'])
            with request("/api/v1/apps/board_game_agent/pdf", method="HEAD") as response:
                check("PDF HEAD", response.status == 200 and response.read() == b"")
            start = time.monotonic()
            with request("/api/v1/apps/board_game_agent/stream") as response:
                check("SSE is not buffered", response.readline() == b"data: first\n" and time.monotonic() - start < .8)
                response.read()
            connection = http.client.HTTPConnection("127.0.0.1", int(port), timeout=5)
            try:
                connection.request("GET", "/api/powersync/socket", headers={"Upgrade": "websocket", "Connection": "Upgrade"})
                check("WebSocket upgrade", connection.getresponse().status == 101)
            finally:
                connection.close()
            with request("/api/ai/request", headers={"X-Board-Game-Request": "1", "Origin": "https://evil.example", "X-BGA-AI-Target": "https://www.loomex.lol/v1/models"}) as response:
                check("BYOK origin rejected", response.status == 403)
            with request("/api/ai/request", headers={"X-Board-Game-Request": "1", "Origin": "https://games.example.test", "X-BGA-AI-Target": "https://127.0.0.1/v1/models"}) as response:
                check("BYOK unsafe target rejected", response.status == 403)
            for image in (web_image, ai_image):
                info = json.loads(run("image", "inspect", image))[0]
                check("non-root " + image, info["Config"]["User"] == "65532:65532")
                if image == ai_image and ai_input_digest is not None:
                    check("relay source inputs", (info["Config"].get("Labels") or {}).get(
                        "io.board-game-agent.build-inputs") == ai_input_digest)
            record = {"passed": True, "checks": checks, "realNasDeployed": False, "businessSuite": "not_run"}
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
            print(json.dumps(record, indent=2))
    except Exception as error:
        states = []
        for container in created:
            result = subprocess.run(["docker", "logs", "--tail", "30", container], capture_output=True, text=True, timeout=30)
            states.append({"container": container, "log": (result.stdout + result.stderr)[-6000:]})
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps({"passed": False, "checks": checks, "errorType": type(error).__name__,
                                      "containers": states}, indent=2) + "\n", encoding="utf-8")
        raise
    finally:
        for container in reversed(created):
            subprocess.run(["docker", "rm", "-f", container], capture_output=True, timeout=30)
        subprocess.run(["docker", "network", "rm", prefix], capture_output=True, timeout=30)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web-image", required=True)
    parser.add_argument("--ai-image", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ai-input-digest")
    parser.add_argument("--expected-version")
    parser.add_argument("--previous-web-image")
    args = parser.parse_args()
    verify(args.web_image, args.ai_image, args.output, args.ai_input_digest, args.expected_version, args.previous_web_image)
