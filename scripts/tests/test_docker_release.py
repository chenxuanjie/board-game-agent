"""Offline packaging tests. FakeDocker records calls; it builds no real image."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import tarfile
from docker_fixtures import write_image_archive

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("docker_release", ROOT / "scripts/build-docker-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class FakeDocker:
    def __init__(self):
        self.calls = []
        self.builds = []
        self.os = "linux"
        self.arch = "amd64"
        self.exists = False
        self.fail_build = 0
        self.empty_save = False
        self.invalid_save = False

    def run(self, *args, **kwargs):
        self.calls.append(args)
        value, code = "", 0
        if args[0] == "info":
            value = self.os
        elif args[:2] == ("image", "inspect"):
            if len(args) == 3:
                code = 0 if self.exists else 1
            else:
                value = json.dumps([{"Os": "linux", "Architecture": self.arch, "Id": "sha256:" + char * 64} for char in ("a", "b")])
        elif args[:2] == ("image", "save"):
            target = Path(args[args.index("--output") + 1])
            if self.empty_save or self.invalid_save:
                target.write_bytes(b"" if self.empty_save else b"not a Docker export")
            else:
                write_image_archive(target, args[args.index("--output") + 2:], self.arch)
        return subprocess.CompletedProcess(args, code, value, "")

    def build(self, *args):
        self.builds.append(args)
        if self.fail_build == len(self.builds):
            raise release.ReleaseError("Simulated build failure")


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "board-game-agent"
        self.root.mkdir()
        (self.root / "pubspec.yaml").write_text("name: fixture\nversion: 4.1.0+37\n")
        for name in ("docker-compose.yml", "packaging/docker/deploy.sh", "packaging/docker/README.images.md", "packaging/docker/.env.example"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        self.docker = FakeDocker()
        self.output = self.root / "release"
        self.git = patch.object(release, "git_state", return_value=("abcdef1234567890", True))
        self.git.start()
        self.addCleanup(self.git.stop)

    def build(self, **kwargs):
        return release.build_release(root=self.root, output=self.output, tag="4.1.0-37-test", docker=self.docker, **kwargs)

    def test_only_one_fixed_tar_is_delivered_with_small_support_files(self):
        archive = self.build()
        self.assertEqual(archive.name, 'board-game-agent-linux-amd64-images.tar')
        self.assertEqual(len(self.docker.builds), 2)
        for args in self.docker.builds:
            self.assertIn('--load', args)
            self.assertIn('linux/amd64', args)
        self.assertFalse(any('push' in call or 'compose' in call or 'run' in call for call in self.docker.calls))
        self.assertEqual(list(self.output.glob('*.tar')), [archive])
        self.assertEqual(list(self.output.glob('*.zip')), [])
        support = self.output / 'reports/docker-linux-amd64'
        manifest = json.loads((support / 'release.json').read_text())
        self.assertEqual(manifest['platform'], 'linux/amd64')
        self.assertTrue(manifest['dirtySource'])
        self.assertEqual(manifest['artifact']['sha256'], release.sha256(archive))
        compose = (support / 'docker-compose.yml').read_text(encoding='utf-8')
        self.assertIn('board-game-agent:4.1.0-37-test', compose)
        self.assertIn('board-game-agent-web-account:4.1.0-37-test', compose)
        self.assertNotIn('${', compose)
        self.assertIn('cznas.pp.ua:192.168.1.55', compose)
        self.assertIn('/data/comments', compose)
        self.assertEqual(compose.count('user: "1028:100"'), 2)
        self.assertIn('8887:8080', compose)
        self.assertIn('WEB_PUBLIC_ORIGIN: "https://cznas.pp.ua:18887"', compose)
        self.assertIn('WEB_ALLOW_INSECURE_HTTP: "false"', compose)
        self.assertIn('AI_ALLOWED_ORIGINS: "https://api.openai.com,https://api.deepseek.com,https://www.loomex.lol,https://loomex.lol"', compose)
        self.assertFalse((support / '.env.example').exists())
        self.assertNotIn(b'\r', (support / 'image-tag.txt').read_bytes())
        self.assertNotIn(b'\r', (support / 'image-platform.txt').read_bytes())
        for line in (support / 'checksums.sha256').read_text().splitlines():
            checksum, name = line.split('  ', 1)
            self.assertEqual(release.sha256(support / name), checksum)
        timings = json.loads((support / 'timings.json').read_text())['timings']
        self.assertIn('totalSeconds', timings)
        self.assertNotIn('zipSeconds', timings)

    def test_synology_yaml_contains_host_settings_and_escapes_yaml_scalars(self):
        configured = release.synology_compose(self.root, {'imageTag': 'matching-release', 'platform': 'linux/amd64'}, {
            'LIBRARY_PATH': '/volume1/games # real library',
            'WEB_PUBLIC_ORIGIN': 'http://192.168.1.9:8887',
            'WEB_ALLOW_INSECURE_HTTP': 'true',
        })
        self.assertIn('source: "/volume1/games # real library"', configured)
        self.assertIn('WEB_PUBLIC_ORIGIN: "http://192.168.1.9:8887"', configured)
        self.assertIn('WEB_ALLOW_INSECURE_HTTP: "true"', configured)
        self.assertNotIn('${', configured)

    def test_wrong_architecture_cannot_be_exported(self):
        self.docker.arch = "arm64"
        with self.assertRaisesRegex(release.ReleaseError, "platform"):
            self.build()
        self.assertFalse(any(call[:2] == ("image", "save") for call in self.docker.calls))
        self.assertFalse(self.output.exists())

    def test_existing_images_are_never_overwritten(self):
        self.docker.exists = True
        with self.assertRaisesRegex(release.ReleaseError, "already exists"):
            self.build()
        self.assertEqual(self.docker.builds, [])

    def test_second_image_failure_does_not_publish_partial_bundle(self):
        self.docker.fail_build = 2
        with self.assertRaises(release.ReleaseError):
            self.build()
        self.assertFalse(self.output.exists())

    def test_windows_engine_is_rejected_before_build(self):
        self.docker.os = "windows"
        with self.assertRaisesRegex(release.ReleaseError, "Linux Docker engine"):
            self.build()
        self.assertEqual(self.docker.builds, [])

    def test_failed_next_build_preserves_previous_complete_delivery(self):
        previous = self.build()
        content = previous.read_bytes()
        self.docker.fail_build = len(self.docker.builds) + 2
        with self.assertRaises(release.ReleaseError):
            release.build_release(root=self.root, output=self.output, tag='next-failed', docker=self.docker)
        self.assertEqual(previous.read_bytes(), content)
        self.assertTrue((self.output / 'board-game-agent-linux-amd64-images.tar').exists())

    def test_successful_next_build_replaces_previous_local_delivery_only(self):
        previous = self.build()
        support = self.output / 'reports/docker-linux-amd64'
        for name in ('validation.json', 'live-nas-validation.json'):
            (support / name).write_text('{"passed":true}')
        current = release.build_release(root=self.root, output=self.output, tag='next-success', docker=self.docker)
        self.assertEqual(previous, current)
        self.assertEqual(list(self.output.glob('*.tar')), [current])
        self.assertEqual(list(self.output.glob('*.zip')), [])
        self.assertFalse((support / 'validation.json').exists())
        self.assertFalse((support / 'live-nas-validation.json').exists())

    def test_empty_export_leaves_no_release_zip(self):
        self.docker.empty_save = True
        with self.assertRaisesRegex(release.ReleaseError, "archive"):
            self.build()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_existing_import_file_is_replaced_instead_of_adding_a_version(self):
        previous = self.build()
        content = previous.read_bytes()
        current = release.build_release(root=self.root, output=self.output, tag='replacement', docker=self.docker)
        self.assertEqual(previous, current)
        self.assertNotEqual(current.read_bytes(), content)
        self.assertEqual(len(list(self.output.glob('*.tar'))), 1)

    def test_invalid_export_does_not_replace_the_existing_import_file(self):
        previous = self.build()
        content = previous.read_bytes()
        self.docker.invalid_save = True
        with self.assertRaises((ValueError, tarfile.TarError)):
            release.build_release(root=self.root, output=self.output, tag='invalid-export', docker=self.docker)
        self.assertEqual(previous.read_bytes(), content)

    def test_invalid_tag_and_unsupported_platform_never_build(self):
        for kwargs in ({"tag": "bad;command"}, {"platform": "windows/amd64"}):
            with self.assertRaises(release.ReleaseError):
                release.build_release(root=self.root, output=self.output, docker=self.docker, **kwargs)
        self.assertEqual(self.docker.builds, [])

    def test_no_docker_reports_no_image_instead_of_creating_source_only_release(self):
        with patch.object(release.shutil, "which", return_value=None), self.assertRaisesRegex(release.ReleaseError, "Docker CLI not found"):
            release.Docker(self.root)


class BuildContextTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.root = self.workspace / 'board-game-agent'
        self.stage = self.workspace / 'isolated'
        for name in ('Dockerfile', 'Dockerfile.dockerignore', 'pubspec.lock', 'lib/main.dart',
                     'web/index.html', 'services/web_account/app.py', 'packaging/docker/nginx.conf', 'packaging/docker/nginx-main.conf',
                     'assets/catalog.json', 'assets/games/sample/game.json',
                     'assets/games/sample/docs/private.pdf', '.env', 'tmp/private.txt',
                     '../unrelated-project/private.txt', '../shared_packages/example/lib/client.dart',
                     '../shared_packages/example/.env', '../shared_packages/example/build/private.txt'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
        (self.workspace / 'shared_packages/example/pubspec.yaml').write_text('name: example\n')
        (self.root / 'pubspec.yaml').write_text('''name: fixture
dependencies:
  example:
    path: ../shared_packages/example
flutter:
  assets:
    - assets/catalog.json
    - assets/games/sample/game.json
    - path: assets/games/sample/docs/private.pdf
      platforms: [windows]
''')
        (self.root / 'scripts').mkdir()
        shutil.copyfile(ROOT / 'scripts/prepare-web-assets.py', self.root / 'scripts/prepare-web-assets.py')

    def test_context_includes_runtime_assets_and_recursive_dependencies_only(self):
        release.stage_build_context(self.root, self.stage)
        names = {p.relative_to(self.stage).as_posix() for p in self.stage.rglob('*') if p.is_file()}
        self.assertIn('board-game-agent/assets/catalog.json', names)
        self.assertIn('shared_packages/example/lib/client.dart', names)
        self.assertFalse(any('.env' in p or '/docs/' in p or '/build/' in p or 'unrelated-project' in p or '/tmp/' in p for p in names))

    def test_dependency_outside_workspace_is_rejected(self):
        manifest = self.root / 'pubspec.yaml'
        manifest.write_text(manifest.read_text().replace('../shared_packages/example', '../../outside'))
        with self.assertRaisesRegex(release.ReleaseError, 'escaped'):
            release.stage_build_context(self.root, self.stage)


if __name__ == "__main__":
    unittest.main()
