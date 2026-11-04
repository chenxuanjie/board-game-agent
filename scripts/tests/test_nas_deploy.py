"""The retired NAS importer never invokes Docker or changes retained files."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.name == 'posix', 'Execute on Linux/WSL for POSIX shell coverage')
class NasDeployTests(unittest.TestCase):
    def test_retired_importer_stops_before_docker_or_configuration_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            before = {'images.tar': b'previous archive', '.env': b'IMAGE_TAG=old',
                      'docker-compose.yml': b'previous deployment'}
            for name, value in before.items():
                (root / name).write_bytes(value)
            result = subprocess.run(['/bin/sh', str(ROOT / 'packaging/docker/deploy.sh')],
                                    cwd=root, env=dict(os.environ, PATH=''),
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn('retired', result.stderr)
            self.assertEqual({p.name: p.read_bytes() for p in root.iterdir()}, before)


if __name__ == '__main__':
    unittest.main()
