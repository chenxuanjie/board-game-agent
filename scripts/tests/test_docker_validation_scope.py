"""Retired delivery commands must stop before touching Docker or artifacts."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class RetiredDeliveryTests(unittest.TestCase):
    def test_python_commands_fail_without_touching_existing_outputs(self):
        for name, arguments in (
            ("build-docker-release.py", ["--output", "release"]),
            ("verify-docker-release.py", ["--archive", "release/images.tar", "--full-validation"]),
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                cwd = Path(temporary)
                (cwd / "release").mkdir()
                previous = cwd / "release/images.tar"
                previous.write_bytes(b"previous delivery")
                # No project files or Docker CLI: retirement must be the first check.
                env = dict(os.environ, PATH="")
                result = subprocess.run([sys.executable, str(ROOT / "scripts" / name), *arguments],
                                        cwd=cwd, env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("retired", result.stderr)
                self.assertIn("docs/web-ghcr.md", result.stderr)
                self.assertEqual(previous.read_bytes(), b"previous delivery")
                self.assertEqual(list((cwd / "release").iterdir()), [previous])

    def test_imported_legacy_builder_also_refuses_before_side_effects(self):
        spec = importlib.util.spec_from_file_location("retired_builder", ROOT / "scripts/build-docker-release.py")
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        with patch('subprocess.run', side_effect=AssertionError('must not invoke Docker')):
            with self.assertRaisesRegex(builder.ReleaseError, 'retired'):
                builder.build_release(root=Path('missing-project'), docker=object())

    @unittest.skipUnless(shutil.which('pwsh'), 'PowerShell 7 is unavailable')
    def test_powershell_wrappers_do_not_invoke_a_publisher_or_create_outputs(self):
        for name, arguments in (
            ('build-docker-release.ps1', ['-Mode', 'build', '-Publisher', 'missing-publisher.ps1']),
            ('package-docker.ps1', ['-OutputDirectory', 'new-output']),
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                result = subprocess.run([shutil.which('pwsh'), '-NoProfile', '-File',
                                         str(ROOT / 'scripts' / name), *arguments], cwd=temporary,
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn('retired', result.stderr)
                self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_old_compose_files_have_no_runtime_services_or_builds(self):
        import yaml
        for name in ('docker-compose.yml', 'docker-compose.build.yml'):
            document = yaml.safe_load((ROOT / name).read_text())
            self.assertEqual(document['services'], {})
            self.assertIn(':?Legacy Web Compose is retired', document['name'])


if __name__ == '__main__':
    unittest.main()
