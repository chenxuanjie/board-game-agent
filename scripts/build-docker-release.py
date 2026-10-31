"""Build two Linux runtime images and replace one fixed Docker-import TAR.

Requires Python 3 + Docker Engine/Buildx. Never connects to NAS or installs Docker.
The default target matches the existing USV Ground Station x86-64 executable.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tarfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_retention import cleanup, inspect_docker_archive, linked
from build_diagnostics import TaskLog
PLATFORMS = ("linux/amd64", "linux/arm64")
REPOSITORIES = ("board-game-agent", "board-game-agent-web-account")


class ReleaseError(Exception):
    pass


class Docker:
    def __init__(self, root):
        self.root = root
        self.log = TaskLog(root, 'docker-build')
        self.binary = shutil.which("docker")
        if not self.binary:
            raise ReleaseError("Docker CLI not found. Use a build computer with Docker Engine and Buildx; no image was built.")

    def preflight(self):
        # Respect this process's configured proxy. Never log proxy credentials
        # or token responses. Failure stops before copying/building any inputs.
        self.log.run('proxy-registry-preflight',
                     [sys.executable, str(ROOT / 'scripts/check-docker-proxy.py')], timeout=120)

    def ready(self):
        self.log.run('docker-environment-ready',
                     [sys.executable, str(ROOT / 'scripts/docker_environment.py')], timeout=900)

    def run(self, *args, check=True, timeout=120):
        if check:
            return self.log.run('docker-' + '-'.join(args[:2]).replace('/', '-'),
                                [self.binary, *args], cwd=self.root, capture=True, timeout=timeout)
        result = subprocess.run([self.binary, *args], cwd=self.root, capture_output=True,
                                text=True, timeout=timeout)
        return result

    def build(self, *args):
        # Persist plain build progress; credentials are never passed as build args.
        # Materialize a small allowlisted context: never send the whole parent
        # workspace (or rely solely on daemon-specific ignore-file discovery).
        with tempfile.TemporaryDirectory(prefix="bga-build-inputs-") as temporary:
            context = Path(temporary)
            stage_build_context(Path(self.root), context)
            arguments = list(args)
            file_index = arguments.index("--file") + 1
            relative = Path(arguments[file_index]).relative_to(self.root)
            arguments[file_index] = str(context / "board-game-agent" / relative)
            arguments[-1] = str(context if relative == Path("Dockerfile") else context / "board-game-agent")
            self.log.run('image-build', [self.binary, "buildx", "build", '--progress=plain', *arguments],
                         cwd=self.root, timeout=14400)


def stage_build_context(root, destination):
    ignored = {".git", ".dart_tool", "build", "node_modules", ".idea", ".pub-cache", ".pub",
               "coverage", "test", "tests", "example", "examples", ".gradle", "keystore", "__pycache__"}
    private = {".env", "pubspec_overrides.yaml", "key.properties", "local.properties", "webdav.local.json"}
    def copy(source, target, *, package_root=False):
        if source.is_symlink():
            raise ReleaseError(f"Build input cannot be a symbolic link: {source}")
        if (source.name in ignored and not package_root) or source.name in private or source.suffix in {".jks", ".keystore", ".p12", ".pfx", ".pyc", ".log"}:
            return
        if source.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            for child in source.iterdir():
                copy(child, target / child.name)
        else:
            if source.suffix.lower() == ".pdf" or ("games" in source.parts and "docs" in source.parts):
                raise ReleaseError("Game documents cannot enter the Web build context")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
    project = destination / "board-game-agent"
    for name in ("Dockerfile", "Dockerfile.dockerignore", "pubspec.yaml", "pubspec.lock", "lib", "web",
                 "scripts/prepare-web-assets.py", "services/web_account", "packaging/docker/nginx.conf", "packaging/docker/nginx-main.conf"):
        copy(root / name, project / name)
    for name in ("packaging/docker/start-web.sh", "packaging/docker/Dockerfile.ai"):
        if (root / name).is_file():
            copy(root / name, project / name)
    spec = importlib.util.spec_from_file_location("web_asset_plan", root / "scripts/prepare-web-assets.py")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    plan = helper.plan((root / "pubspec.yaml").read_text(encoding="utf-8-sig"))
    for name in plan["paths"]:
        copy(root / name, project / name)
    pending, visited = [root], set()
    while pending:
        package = pending.pop().resolve()
        if package in visited:
            continue
        if not package.is_relative_to(root.parent):
            raise ReleaseError("Path dependency escaped the workspace")
        visited.add(package)
        if package != root:
            copy(package, destination / package.relative_to(root.parent), package_root=True)
        for match in re.finditer(r"(?m)^\s+path:\s*[\"']?((?:\.{1,2}/|packages/)[^\s\"'#]+)",
                                 (package / "pubspec.yaml").read_text(encoding="utf-8-sig")):
            pending.append(package / match[1])
    print(f"Prepared allowlisted build context: {sum(p.stat().st_size for p in destination.rglob('*') if p.is_file()) / 1024**2:.1f} MiB", flush=True)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_state(root):
    def git(*args):
        result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=10)
        if result.returncode:
            raise ReleaseError("Cannot record the source revision")
        return result.stdout.strip()
    return git("rev-parse", "HEAD"), bool(git("status", "--porcelain"))


def synology_compose(root, manifest, settings=None):
    """Render one self-contained GUI deployment file, without Compose variables."""
    defaults = {}
    for line in (root / 'packaging/docker/.env.example').read_text(encoding='utf-8-sig').splitlines():
        if line and not line.startswith('#') and '=' in line:
            name, value = line.split('=', 1)
            defaults[name] = value
    defaults.update(settings or {})
    if any(not str(defaults.get(key, '')).isdigit() or not 1 <= int(defaults[key]) <= 2147483647
           for key in ('NAS_READER_UID', 'NAS_READER_GID')):
        raise ReleaseError('Use the existing NAS owner numeric UID/GID, without root or permission changes')
    values = {
        '${ACCOUNT_SHARED_FOLDER:-friend}': defaults['ACCOUNT_SHARED_FOLDER'],
        '${SYNOLOGY_HOST:-cznas.pp.ua}': defaults['SYNOLOGY_HOST'],
        '${SYNOLOGY_LAN_IP:-192.168.1.55}': defaults['SYNOLOGY_LAN_IP'],
        '${COMMENTS_PATH:?Set the existing NAS comments folder}': defaults['COMMENTS_PATH'],
        '${SYNOLOGY_IDENTITY_ORIGIN:-${SYNOLOGY_ORIGIN}}': defaults['SYNOLOGY_IDENTITY_ORIGIN'],
        '${IMAGE_TAG:?Set the imported release image tag}': manifest['imageTag'],
        '${BGA_IMAGE_PLATFORM:-linux/amd64}': manifest['platform'],
        '${LIBRARY_PATH:?Set the existing NAS library folder}': defaults['LIBRARY_PATH'],
        '${SYNOLOGY_ORIGIN:?Set the trusted DSM HTTPS origin}': defaults['SYNOLOGY_ORIGIN'],
        '${WEB_PUBLIC_ORIGIN:?Set the browser site origin}': defaults['WEB_PUBLIC_ORIGIN'],
        '${WEB_ALLOW_INSECURE_HTTP:-false}': defaults['WEB_ALLOW_INSECURE_HTTP'],
        '${AI_ALLOWED_ORIGINS:-https://api.openai.com,https://api.deepseek.com,https://www.loomex.lol,https://loomex.lol}': defaults['AI_ALLOWED_ORIGINS'],
        '${LIBRARY_NAS_PATH:?Set the matching FileStation library path}': defaults['LIBRARY_NAS_PATH'],
    }
    compose = (root / 'docker-compose.yml').read_text(encoding='utf-8-sig')
    compose = compose.replace('"${NAS_READER_UID:-1028}:${NAS_READER_GID:-100}"',
                              json.dumps(f'{defaults["NAS_READER_UID"]}:{defaults["NAS_READER_GID"]}'))
    compose = compose.replace('"${SYNOLOGY_HOST:-cznas.pp.ua}:${SYNOLOGY_LAN_IP:-192.168.1.55}"',
                              json.dumps(f'{defaults["SYNOLOGY_HOST"]}:{defaults["SYNOLOGY_LAN_IP"]}'))
    compose = compose.replace('"${WEB_PORT:-8887}:8080"', json.dumps(f'{defaults["WEB_PORT"]}:8080'))
    # Image refs need to be quoted as a whole; all other values occupy entire scalars.
    for repository in REPOSITORIES:
        token = repository + ':${IMAGE_TAG:?Set the imported release image tag}'
        compose = compose.replace(token, json.dumps(f'{repository}:{manifest["imageTag"]}'))
    for token, value in values.items():
        compose = compose.replace(token, json.dumps(str(value), ensure_ascii=False))
    if '${' in compose:
        raise ReleaseError('Unresolved variable in Synology Compose')
    return (f'# ===== 桌游伙伴 {manifest.get("applicationVersion", "V5")} · 群晖部署配置 =====\n'
            f'# 对应镜像标签：{manifest["imageTag"]}\n'
            '# 本版识别：端口 8887:8080；两个服务均使用 NAS 读取身份。\n'
            '# 如仍看到 8887:80 或旧镜像标签，说明尚未替换为本文件。\n'
            '# ==========================================\n'
            '# Synology Container Manager: import the matching TAR, then upload this file.\n'
            '# No .env or build tools required. Edit NAS paths and site/DSM URLs here.\n'
            '# Browser URL must match WEB_PUBLIC_ORIGIN; update it if the site address changes.\n'
            f'# Browser entry: {defaults["WEB_PUBLIC_ORIGIN"]}; TLS may terminate at the NAS reverse proxy.\n'
            + compose)


def write_support_files(root, stage, manifest, settings=None):
    """Small unpacked deployment files; never creates an outer ZIP."""
    stage.mkdir(parents=True, exist_ok=True)
    for name, source in {
        'deploy.sh': root / 'packaging/docker/deploy.sh',
        'README.md': root / 'packaging/docker/README.images.md',
    }.items():
        (stage / name).write_text(source.read_text(encoding='utf-8-sig'), encoding='utf-8', newline='\n')
    (stage / 'docker-compose.yml').write_text(synology_compose(root, manifest, settings), encoding='utf-8', newline='\n')
    (stage / 'image-tag.txt').write_text(manifest['imageTag'] + '\n', encoding='ascii', newline='\n')
    (stage / 'image-platform.txt').write_text(manifest['platform'] + '\n', encoding='ascii', newline='\n')
    (stage / 'release.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')
    # Compose is intentionally edited for the deployment host. Hash only immutable
    # release metadata/scripts and the TAR; never reject a user's NAS configuration.
    checksums = ''.join(f'{sha256(stage / name)}  {name}\n' for name in
                        ('README.md', 'deploy.sh', 'image-platform.txt', 'image-tag.txt', 'release.json'))
    checksums += f'{manifest["artifact"]["sha256"]}  ../../{manifest["artifact"]["fileName"]}\n'
    (stage / 'checksums.sha256').write_text(checksums, encoding='ascii', newline='\n')


def build_release(root=ROOT, output=None, platform="linux/amd64", tag=None, docker=None):
    started = time.perf_counter()
    timings = {}
    root = Path(root).resolve()
    output = Path(output or root / "release").resolve()
    if platform not in PLATFORMS:
        raise ReleaseError("Select a single supported Linux image platform")
    match = re.search(r"(?m)^version:\s*([0-9A-Za-z.+-]+)\s*$", (root / "pubspec.yaml").read_text(encoding="utf-8-sig"))
    if not match:
        raise ReleaseError("Missing application version")
    version = match[1]
    revision, dirty = git_state(root)
    built_at = datetime.now(timezone.utc)
    tag = tag or f"{version.replace('+', '-')}-{revision[:7]}{'-dirty' if dirty else ''}-{built_at:%Y%m%d%H%M%S%f}"
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", tag):
        raise ReleaseError("Invalid Docker image tag")
    references = [f"{name}:{tag}" for name in REPOSITORIES]
    destination = output / f"board-game-agent-{platform.replace('/', '-')}-images.tar"
    if linked(destination):
        raise ReleaseError("Import file cannot be a symlink")

    docker = docker or Docker(root)
    if isinstance(docker, Docker):
        docker.ready()
    if docker.run("info", "--format", "{{.OSType}}", timeout=120).stdout.strip() != "linux":
        raise ReleaseError("A running Linux Docker engine is required")
    docker.run("buildx", "version")
    if isinstance(docker, Docker):
        docker.preflight()
    for reference in references:
        if docker.run("image", "inspect", reference, check=False).returncode == 0:
            raise ReleaseError(f"Image tag already exists: {reference}; choose a new tag to preserve rollback")
    labels = ["--label", f"org.opencontainers.image.version={version}",
              "--label", f"org.opencontainers.image.revision={revision}",
              "--label", f"org.opencontainers.image.created={built_at.isoformat()}"]
    builds = ((root / "Dockerfile", root.parent), (root / "services/web_account/Dockerfile", root))
    for reference, (file, context) in zip(references, builds):
        print(f"Building {reference} ({platform})", flush=True)
        stage_started = time.perf_counter()
        docker.build("--load", "--platform", platform, "--tag", reference, *labels,
                     "--file", str(file), str(context))
        timings[reference.split(':', 1)[0] + "BuildSeconds"] = round(time.perf_counter() - stage_started, 3)

    images = json.loads(docker.run("image", "inspect", *references).stdout)
    expected_arch = platform.split("/")[1]
    if len(images) != 2 or any(image.get("Os") != "linux" or image.get("Architecture") != expected_arch for image in images):
        raise ReleaseError("Built image platform does not match the NAS target")
    if any(not re.fullmatch(r"sha256:[a-f0-9]{64}", image.get("Id", "")) for image in images):
        raise ReleaseError("Missing image content ID")

    output.mkdir(parents=True, exist_ok=True)
    support = output / 'reports' / f"docker-{platform.replace('/', '-')}"
    for directory in (output / 'reports', support):
        if linked(directory) or not directory.resolve().is_relative_to(output):
            raise ReleaseError('Unsafe support directory')
    with tempfile.TemporaryDirectory(prefix='.docker-release-', dir=output) as temporary:
        stage = Path(temporary).resolve()
        archive = stage / 'images.tar'
        stage_started = time.perf_counter()
        docker.run('image', 'save', '--output', str(archive), *references, timeout=3600)
        timings['imageExportSeconds'] = round(time.perf_counter() - stage_started, 3)
        if not archive.is_file() or archive.stat().st_size == 0:
            raise ReleaseError('Docker did not export an image archive')
        inspect_docker_archive(archive, platform, references)
        manifest = {'format': 'board-game-agent.docker-images', 'version': 2,
                    'applicationVersion': version, 'sourceRevision': revision, 'dirtySource': dirty,
                    'builtAt': built_at.isoformat(), 'platform': platform, 'imageTag': tag,
                    'buildTimings': dict(timings),
                    'artifact': {'fileName': destination.name, 'size': archive.stat().st_size,
                                 'sha256': sha256(archive)},
                    'images': [{'reference': ref, 'id': image['Id']} for ref, image in zip(references, images)]}
        staged_support = stage / 'support'
        write_support_files(root, staged_support, manifest)
        support.mkdir(parents=True, exist_ok=True)
        for source in staged_support.iterdir():
            if linked(support / source.name):
                raise ReleaseError('Support file cannot be a symlink')
        for name in ('timings.json', 'validation.json', 'live-nas-validation.json', '.env.example'):
            if linked(support / name):
                raise ReleaseError('Report file cannot be a symlink')
        # The old import file stays intact until both builds, export and archive
        # validation finish. Same-filesystem replace never exposes a partial TAR.
        archive.replace(destination)
        for source in staged_support.iterdir():
            source.replace(support / source.name)
        legacy_example = support / '.env.example'
        if legacy_example.exists():
            legacy_example.unlink()
        for name in ('validation.json', 'live-nas-validation.json'):
            stale_validation = support / name
            if stale_validation.exists():
                if linked(stale_validation):
                    raise ReleaseError('Validation report cannot be a symlink')
                stale_validation.unlink()
    timings['totalSeconds'] = round(time.perf_counter() - started, 3)
    (support / 'timings.json').write_text(json.dumps({'archive': destination.name, 'timings': timings}, indent=2) + '\n', encoding='utf-8')
    retained = cleanup(output, ('docker',))
    print(f"Local Docker retention: removed {len(retained['removed'])} old files", flush=True)
    print(f'Docker image import file: {destination}', flush=True)
    print(f'Deployment configuration and reports: {support}', flush=True)
    print('Existing import file replaced after successful validation; no ZIP generated.', flush=True)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=PLATFORMS, default="linux/amd64")
    parser.add_argument("--output", type=Path, default=ROOT / "release")
    parser.add_argument("--image-tag")
    args = parser.parse_args()
    try:
        build_release(output=args.output, platform=args.platform, tag=args.image_tag)
        return 0
    except (ReleaseError, OSError, ValueError, tarfile.TarError, subprocess.SubprocessError) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
