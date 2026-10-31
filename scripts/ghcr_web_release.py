"""Committed dependency snapshots, GHCR metadata and self-contained Web Compose."""
import argparse
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

import yaml

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = Path("packaging/ci/shared-packages.tar.gz")
LOCK = Path("packaging/ci/shared-packages.lock.json")
AI_INPUTS = ("packaging/docker/Dockerfile.ai", "packaging/docker/ai-requirements.lock", "services/web_account/requirements.txt",
             "services/web_account/ai_app.py", "services/web_account/ai_proxy.py")


def ai_input_digest(root=ROOT):
    locked = (root / "packaging/docker/ai-requirements.lock").read_text(encoding="utf-8")
    for requirement in (root / "services/web_account/requirements.txt").read_text(encoding="utf-8-sig").splitlines():
        if requirement.strip() and not requirement.startswith("#") and not any(
                line.split(" ", 1)[0] == requirement.strip() for line in locked.splitlines()):
            raise ValueError("Update the relay dependency lock before publishing")
    value = hashlib.sha256(b"linux/amd64\0")
    for name in AI_INPUTS:
        value.update(name.encode() + b"\0")
        value.update((root / name).read_bytes().replace(b"\r\n", b"\n") + b"\0")
    return value.hexdigest()


def ai_image_exists(image):
    match = re.fullmatch(r"ghcr\.io/([a-z0-9_./-]+):(inputs-[a-f0-9]{64})", image)
    if not match:
        raise ValueError("Expected the input-addressed GHCR relay image")
    repository, tag = match.groups()
    for attempt in range(3):
        try:
            with urllib.request.urlopen(
                    "https://ghcr.io/token?service=ghcr.io&scope=repository:" + repository + ":pull",
                    timeout=15) as response:
                token = json.load(response)["token"]
            request = urllib.request.Request("https://ghcr.io/v2/" + repository + "/manifests/" + tag,
                method="HEAD", headers={"Authorization": "Bearer " + token,
                "Accept": "application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json"})
            with urllib.request.urlopen(request, timeout=15) as response:
                return response.status == 200
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return False
            if error.code < 500 or attempt == 2:
                raise RuntimeError("Cannot check relay registry access (HTTP " + str(error.code) + ")") from None
        except (urllib.error.URLError, TimeoutError):
            if attempt == 2:
                raise RuntimeError("Cannot check relay registry connectivity") from None
        time.sleep(attempt + 1)


def git(folder, *args, binary=False):
    result = subprocess.run(["git", "-C", str(folder), *args], check=True, capture_output=True)
    return result.stdout if binary else result.stdout.decode().strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def dependencies(root):
    seen = set()
    pending = [root]
    while pending:
        folder = pending.pop().resolve()
        if folder in seen:
            continue
        if not folder.is_relative_to(root.parent):
            raise ValueError("Path dependency escaped the workspace")
        seen.add(folder)
        document = yaml.safe_load((folder / "pubspec.yaml").read_text(encoding="utf-8-sig"))
        for section in ("dependencies", "dev_dependencies", "dependency_overrides"):
            for value in (document.get(section) or {}).values():
                if isinstance(value, dict) and "path" in value:
                    pending.append(folder / value["path"])
        if not folder.is_relative_to(root):
            yield folder, document


def snapshot(root=ROOT):
    packages = []
    files = {}
    for folder, document in sorted(dependencies(root), key=lambda item: str(item[0])):
        if git(folder, "status", "--porcelain", "--untracked-files=all"):
            raise ValueError(f"Commit dependency changes first: {document['name']}")
        commit = git(folder, "rev-parse", "HEAD")
        prefix = folder.relative_to(root.parent).as_posix()
        if not prefix.startswith("shared_packages/"):
            raise ValueError("External dependency must be under shared_packages")
        packages.append({"name": document["name"], "version": document.get("version"),
                         "commit": commit, "path": prefix})
        names = git(folder, "ls-files", "-z").split("\0")
        for name in names:
            if not name or not (name.startswith(("lib/", "assets/")) or
                                name in {"pubspec.yaml", "pubspec.lock", "LICENSE", "NOTICE"}):
                continue
            path = folder / name
            if path.is_symlink() or not path.is_file() or path.stat().st_size > 16 * 1024**2:
                raise ValueError("Unsafe dependency source file")
            if any(part.startswith(".") for part in Path(name).parts):
                raise ValueError("Hidden dependency files cannot enter CI snapshots")
            files[f"{prefix}/{name}"] = path.read_bytes()
    if not packages:
        raise ValueError("No external dependencies found")
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode="wb", filename="", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as archive:
            for name, content in sorted(files.items()):
                item = tarfile.TarInfo(name)
                item.size, item.mode, item.mtime = len(content), 0o644, 0
                archive.addfile(item, io.BytesIO(content))
    packed = output.getvalue()
    (root / SNAPSHOT).parent.mkdir(parents=True, exist_ok=True)
    (root / SNAPSHOT).write_bytes(packed)
    record = {"schemaVersion": 1, "archiveSha256": digest(packed), "packages": packages,
              "files": {name: digest(content) for name, content in sorted(files.items())}}
    (root / LOCK).write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Snapshotted {len(packages)} committed packages; {len(packed)} bytes; no private profiles")


def extract(archive, destination, expected=None):
    found = {}
    for item in archive:
        path = Path(item.name)
        if path.is_absolute() or ".." in path.parts or not (item.isdir() or item.isfile()):
            raise ValueError("Unsafe archive entry")
        if item.isdir():
            continue
        content = archive.extractfile(item).read()
        if expected is not None and expected.get(item.name) != digest(content):
            raise ValueError("Dependency file digest mismatch")
        if item.name in found:
            raise ValueError("Duplicate archive entry")
        found[item.name] = digest(content)
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    if expected is not None and found != expected:
        raise ValueError("Dependency snapshot is incomplete")


def prepare(destination, root=ROOT):
    if destination.exists():
        raise ValueError("Use a new build context directory")
    record = json.loads((root / LOCK).read_text(encoding="utf-8"))
    packed = (root / SNAPSHOT).read_bytes()
    if record["schemaVersion"] != 1 or digest(packed) != record["archiveSha256"]:
        raise ValueError("Dependency archive digest mismatch")
    with tempfile.TemporaryDirectory(prefix="bga-ci-workspace-") as temporary:
        workspace = Path(temporary)
        project = workspace / "board-game-agent"
        project.mkdir()
        with tarfile.open(fileobj=io.BytesIO(git(root, "archive", "HEAD", binary=True))) as archive:
            extract(archive, project)
        with tarfile.open(fileobj=io.BytesIO(packed), mode="r:gz") as archive:
            extract(archive, workspace, record["files"])
        spec = importlib.util.spec_from_file_location("bga_docker_release", root / "scripts/build-docker-release.py")
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        helper.stage_build_context(project, destination)
    print("Prepared allowlisted context from the committed application and pinned dependencies")


def metadata(repository, commit, branch, root=ROOT):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Expected GitHub owner/repository")
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Expected a complete source commit")
    version = str(yaml.safe_load((root / "pubspec.yaml").read_text(encoding="utf-8"))["version"])
    if not re.fullmatch(r"\d+\.\d+\.\d+\+\d+", version):
        raise ValueError("Expected an application version with a build number")
    tag = version.replace("+", "-") + "-" + commit[:12]
    branch_tag = "branch-" + re.sub(r"[^a-z0-9_.-]+", "-", branch.lower()).strip(".-")[:100]
    owner = repository.split("/")[0].lower()
    ai_digest = ai_input_digest(root)
    return {"applicationVersion": version, "sourceRevision": commit, "imageTag": tag,
            "branchTag": branch_tag, "webImage": f"ghcr.io/{repository.lower()}:{tag}",
            "aiInputDigest": ai_digest,
            "aiImage": f"ghcr.io/{owner}/board-game-agent-web-ai:inputs-{ai_digest}"}


def compose(web_image, ai_image):
    for image in (web_image, ai_image):
        if not re.fullmatch(r"ghcr\.io/[a-z0-9_./-]+(?::[a-zA-Z0-9_.-]+|@sha256:[a-f0-9]{64})", image):
            raise ValueError("Expected a fixed GHCR image reference")
    hardened = {"platform": "linux/amd64", "pull_policy": "always", "restart": "unless-stopped",
                "read_only": True, "cap_drop": ["ALL"], "security_opt": ["no-new-privileges:true"],
                "logging": {"driver": "json-file", "options": {"max-size": "10m", "max-file": "3"}}}
    result = {"name": "board-game-agent", "services": {
        "board-game-agent": {**hardened, "image": web_image, "ports": ["8083:8080"],
            "environment": {"APP_SERVICE_UPSTREAM": "http://192.168.1.55:18280"},
            "tmpfs": ["/tmp:rw,nosuid,nodev,size=64m"], "mem_limit": "192m"},
        "web-ai": {**hardened, "image": ai_image,
            "environment": {"WEB_PUBLIC_ORIGIN": "https://cznas.pp.ua:8084",
                "AI_ALLOWED_ORIGINS": "https://api.openai.com,https://api.deepseek.com,https://www.loomex.lol,https://loomex.lol"},
            "tmpfs": ["/tmp:rw,nosuid,nodev,size=32m"], "mem_limit": "256m",
            "healthcheck": {"test": ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2)"],
                "interval": "30s", "timeout": "3s", "retries": 3}},
    }}
    return ("# HTTPS entry: https://cznas.pp.ua:8084; HTTP port: 8083.\n"
            "# Synology reverse proxy: HTTPS 8084 -> HTTP 127.0.0.1:8083.\n"
            "# API board_game_agent.browser_origin must equal the HTTPS entry above.\n"
            "# No NAS library mount, old account gateway, .env, or on-NAS compilation.\n"
            + yaml.safe_dump(result, sort_keys=False, allow_unicode=True))


def nas_compose():
    return ("# Reusable NAS deployment: reapply the project to pull the published NAS channel.\n"
            "# Restarting an existing container alone does not update its image.\n"
            + compose("ghcr.io/chenxuanjie/board-game-agent:nas",
                      "ghcr.io/chenxuanjie/board-game-agent-web-ai:nas"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("snapshot")
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--destination", type=Path, required=True)
    meta_parser = commands.add_parser("metadata")
    meta_parser.add_argument("--repository", required=True)
    meta_parser.add_argument("--commit", required=True)
    meta_parser.add_argument("--branch", required=True)
    meta_parser.add_argument("--github-output", type=Path)
    relay_parser = commands.add_parser("resolve-ai")
    relay_parser.add_argument("--image", required=True)
    relay_parser.add_argument("--github-output", type=Path, required=True)
    compose_parser = commands.add_parser("compose")
    compose_parser.add_argument("--web-image", required=True)
    compose_parser.add_argument("--ai-image", required=True)
    compose_parser.add_argument("--output", type=Path, required=True)
    nas_parser = commands.add_parser("nas-compose")
    nas_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "snapshot":
        snapshot()
    elif args.command == "prepare":
        prepare(args.destination)
    elif args.command == "metadata":
        record = metadata(args.repository, args.commit, args.branch)
        print(json.dumps(record, indent=2))
        if args.github_output:
            with args.github_output.open("a", encoding="utf-8") as output:
                for key, value in record.items():
                    output.write(f"{key}={value}\n")
    elif args.command == "resolve-ai":
        exists = ai_image_exists(args.image)
        with args.github_output.open("a", encoding="utf-8") as output:
            output.write("build=" + ("false" if exists else "true") + "\n")
        print("Reuse published relay inputs" if exists else "Relay inputs are new; build once")
    elif args.command == "nas-compose":
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(nas_compose(), encoding="utf-8")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(compose(args.web_image, args.ai_image), encoding="utf-8")


if __name__ == "__main__":
    main()
