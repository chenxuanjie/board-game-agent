"""Keep one complete local delivery per platform. Never touches remote files."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import tarfile

APP = 'board_game_agent'
VERSION = r'\d+\.\d+\.\d+\+\d+'
NATIVE = re.compile(rf'^{APP}-({VERSION})(\.apk|-windows-x64-setup\.exe)$')
RECORD = re.compile(rf'^{APP}-({VERSION})(-windows)?\.release\.json$')
DOCKER = re.compile(r'^board-game-agent-linux-(amd64|arm64)-images\.tar$')
SOURCE = re.compile(r'^board-game-agent-.+-docker(?:-[0-9-]+)?\.zip$')


def stream_digest(stream):
    checksum = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        checksum.update(chunk)
    return checksum.hexdigest()


def digest(path):
    with path.open('rb') as stream:
        return stream_digest(stream)


def linked(path):
    return path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction())


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def safe_file(root, path):
    path = Path(path)
    # No recursive deletion and no traversal through junctions/symlinks.
    if linked(path) or not path.is_file() or not path.resolve().is_relative_to(root):
        raise ValueError(f'Unsafe release file: {path}')
    return path


def version_key(version):
    return tuple(map(int, re.split(r'[.+]', version)))


def native_keep(root, platform):
    ending = '.apk' if platform == 'android' else '-windows-x64-setup.exe'
    candidates = [p for p in root.iterdir() if NATIVE.fullmatch(p.name) and p.name.endswith(ending)]
    if not candidates:
        return set(), set()
    latest = max(candidates, key=lambda p: version_key(NATIVE.fullmatch(p.name)[1]))
    safe_file(root, latest)
    version = NATIVE.fullmatch(latest.name)[1]
    record = root / f'{APP}-{version}{"-windows" if platform == "windows" else ""}.release.json'
    metadata = read_json(safe_file(root, record))
    artifacts = metadata.get('artifacts', [])
    if (metadata.get('appId') != APP or len(artifacts) != 1
            or artifacts[0].get('platform') != platform
            or artifacts[0].get('path', '').rsplit('/', 1)[-1] != latest.name
            or f'{metadata.get("versionName")}+{metadata.get("buildNumber")}' != version
            or artifacts[0].get('size') != latest.stat().st_size
            or artifacts[0].get('sha256') != digest(latest)):
        raise ValueError(f'Latest {platform} package is not complete/verified; old versions were retained')
    keep = {latest, record}
    if platform == 'windows':
        manifest = root / f'{APP}-windows-x64-manifest.json'
        data = read_json(safe_file(root, manifest))
        artifact = data.get('artifacts', [None])[0]
        if (data.get('appId') != APP or data.get('versionName') != metadata['versionName']
                or data.get('buildNumber') != metadata['buildNumber'] or not isinstance(artifact, dict)
                or artifact.get('path') != latest.name or artifact.get('sha256') != artifacts[0]['sha256']
                or artifact.get('size') != latest.stat().st_size):
            raise ValueError('Windows manifest does not match the latest complete installer')
        keep.add(manifest)
    old = set(candidates) - keep
    for path in root.iterdir():
        match = RECORD.fullmatch(path.name)
        if match and bool(match[2]) == (platform == 'windows') and path not in keep:
            old.add(path)
    return keep, old


def inspect_docker_archive(path, expected_platform=None, expected_references=None):
    """Validate a Docker-save TAR without extracting or executing its contents."""
    with tarfile.open(path, 'r:*') as archive:
        def member(name):
            if not isinstance(name, str) or PurePosixPath(name).is_absolute() or '..' in PurePosixPath(name).parts:
                raise ValueError('Unsafe Docker archive member')
            item = archive.getmember(name)
            if not item.isfile():
                raise ValueError('Docker archive member must be a regular file')
            return item
        def document(name):
            item = member(name)
            if item.size > 1024 * 1024:
                raise ValueError('Docker archive metadata is too large')
            with archive.extractfile(item) as stream:
                return json.load(stream)
        manifest = document('manifest.json')
        if not isinstance(manifest, list) or len(manifest) != 2:
            raise ValueError('Expected the Web and account gateway images')
        references, platforms = [], set()
        for image in manifest:
            tags = image.get('RepoTags')
            if not isinstance(tags, list) or len(tags) != 1 or not isinstance(tags[0], str):
                raise ValueError('Missing image reference')
            references.extend(tags)
            config = document(image['Config'])
            platforms.add(f"{config.get('os')}/{config.get('architecture')}")
            if not image.get('Layers'):
                raise ValueError('Missing Docker image layers')
            for layer in image['Layers']:
                if member(layer).size == 0:
                    raise ValueError('Empty Docker image layer')
        if {ref.split(':', 1)[0] for ref in references} != {'board-game-agent', 'board-game-agent-web-account'}:
            raise ValueError('Unexpected image repositories')
        if len(platforms) != 1 or not platforms <= {'linux/amd64', 'linux/arm64'}:
            raise ValueError('Invalid Docker image platform')
        platform = next(iter(platforms))
        if expected_platform and platform != expected_platform:
            raise ValueError('Docker export platform mismatch')
        if expected_references and sorted(references) != sorted(expected_references):
            raise ValueError('Docker export references mismatch')
        return {'platform': platform, 'references': references}


def cleanup(root, platforms=('android', 'windows', 'docker'), *, dry_run=False):
    original = Path(root).absolute()
    if linked(original):
        raise ValueError('Release directory cannot be a symlink')
    root = original.resolve(strict=True)
    keep, remove = set(), set()
    reports = root / 'reports'
    if reports.exists() and (linked(reports) or not reports.resolve().is_relative_to(root)):
        raise ValueError('Unsafe reports directory')
    for platform in platforms:
        if platform in ('android', 'windows'):
            retained, obsolete = native_keep(root, platform)
            keep.update(retained); remove.update(obsolete)
        elif platform == 'docker':
            for latest in root.iterdir():
                match = DOCKER.fullmatch(latest.name)
                if not match:
                    continue
                arch = match[1]
                inspect_docker_archive(safe_file(root, latest), f'linux/{arch}')
                metadata = reports / f'docker-linux-{arch}' / 'release.json'
                if metadata.exists():
                    data = read_json(safe_file(root, metadata))
                    artifact = data.get('artifact', {})
                    if (artifact.get('fileName') != latest.name or artifact.get('size') != latest.stat().st_size
                            or artifact.get('sha256') != digest(latest)):
                        raise ValueError('Docker TAR does not match its release record')
                keep.add(latest)
                for path in root.iterdir():
                    if path != latest and (re.fullmatch(rf'board-game-agent-.+-linux-{arch}-images\.(zip|tar)', path.name)
                                           or SOURCE.fullmatch(path.name) or path.name == 'docker-validation.json'):
                        remove.add(path)
                if reports.exists():
                    for path in reports.iterdir():
                        if re.fullmatch(rf'board-game-agent-.+-linux-{arch}-images\.(timings\.json|validation\.json|zip\.sha256)', path.name):
                            remove.add(path)
        else:
            raise ValueError(f'Unknown platform: {platform}')
    for package in list(remove):
        if package.suffix == '.zip':
            for suffix in ('.timings.json', '.validation.json', '.zip.sha256'):
                companion = package.with_suffix(suffix)
                if companion.exists():
                    remove.add(companion)
    for path in remove:
        safe_file(root, path)
    freed = sum(p.stat().st_size for p in remove)
    if not dry_run:
        for path in sorted(remove):
            path.unlink()
    return {'kept': sorted(p.name for p in keep), 'removed': sorted(p.name for p in remove),
            'freedBytes': freed, 'reportsMoved': 0, 'dryRun': dry_run}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(__file__).resolve().parents[1] / 'release')
    parser.add_argument('--platform', choices=('all', 'android', 'windows', 'docker'), default='all')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    selected = ('android', 'windows', 'docker') if args.platform == 'all' else (args.platform,)
    try:
        print(json.dumps(cleanup(args.directory, selected, dry_run=args.dry_run), indent=2))
    except (ValueError, OSError, KeyError, tarfile.TarError) as error:
        parser.exit(1, f'Cleanup stopped; no unverified package was selected: {error}\n')


if __name__ == '__main__':
    main()
