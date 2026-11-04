"""Build-context boundaries; no image compilation or Docker daemon required."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("docker_build_context", ROOT / "scripts/docker_build_context.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


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

    def test_build_number_changes_do_not_invalidate_dependency_metadata(self):
        manifest = self.root / 'pubspec.yaml'
        text = manifest.read_text().replace('name: fixture', 'name: fixture\nversion: 5.0.0+54')
        manifest.write_text(text)
        release.stage_build_context(self.root, self.stage)
        cached = (self.stage / 'dependency-manifests/board-game-agent/pubspec.yaml').read_text()
        self.assertIn('version: 0.0.0', cached)
        self.assertIn('version: 5.0.0+54', (self.stage / 'board-game-agent/pubspec.yaml').read_text())
        manifest.write_text(text.replace('+54', '+55'))
        another = self.workspace / 'second-context'
        release.stage_build_context(self.root, another)
        self.assertEqual((another / 'dependency-manifests/board-game-agent/pubspec.yaml').read_text(), cached)
        self.assertIn('version: 5.0.0+55', (another / 'board-game-agent/pubspec.yaml').read_text())


if __name__ == "__main__":
    unittest.main()
