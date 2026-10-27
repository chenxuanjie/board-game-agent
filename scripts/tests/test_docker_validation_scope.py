"""Exercise default artifact verification without Docker or business fixtures."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from docker_fixtures import write_image_archive

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from release_retention import digest


class ValidationScopeTests(unittest.TestCase):
    def test_default_skips_business_but_still_rejects_wrong_imported_image(self):
        for corrupt in (False, True):
            with self.subTest(corrupt=corrupt), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                bundle = root / 'board-game-agent-linux-amd64-images.tar'
                references = ['board-game-agent:fixture', 'board-game-agent-web-account:fixture']
                write_image_archive(bundle, references)
                support = root / 'reports/docker-linux-amd64'
                support.mkdir(parents=True)
                release = {
                    'artifact': {'fileName': bundle.name, 'sha256': digest(bundle)},
                    'images': [{'reference': ref, 'id': f'sha256:fixture-{i}'}
                               for i, ref in enumerate(references)],
                }
                (support / 'release.json').write_text(json.dumps(release))
                (support / 'docker-compose.yml').write_text('services: {}\n')
                calls = []

                def execute(command, **kwargs):
                    calls.append(command)
                    if 'compose' in command:
                        self.assertIn('config', command)
                        value = {'services': {'web': {'image': references[0]},
                                              'api': {'image': references[1]}}}
                    elif command[:3] == ['docker', 'image', 'load']:
                        value = None
                    elif command[:3] == ['docker', 'image', 'inspect']:
                        index = references.index(command[-1])
                        value = [{'Id': 'sha256:wrong' if corrupt else f'sha256:fixture-{index}',
                                  'Os': 'linux', 'Architecture': 'amd64'}]
                    else:
                        raise AssertionError(f'Unexpected runtime/business command: {command}')
                    return subprocess.CompletedProcess(command, 0, json.dumps(value), '')

                with patch.object(sys, 'argv', ['verify-docker-release.py', '--archive', str(bundle)]), \
                        patch('subprocess.run', side_effect=execute), \
                        contextlib.redirect_stdout(io.StringIO()):
                    if corrupt:
                        with self.assertRaises(AssertionError):
                            runpy.run_path(str(SCRIPTS / 'verify-docker-release.py'), run_name='__main__')
                        self.assertFalse((support / 'validation.json').exists())
                    else:
                        with self.assertRaises(SystemExit) as stopped:
                            runpy.run_path(str(SCRIPTS / 'verify-docker-release.py'), run_name='__main__')
                        self.assertEqual(stopped.exception.code, 0)
                        result = json.loads((support / 'validation.json').read_text())
                        self.assertTrue(result['passed'])
                        self.assertEqual(result['businessTests'], 'not_run')
                        self.assertEqual(result['validationScope'], 'artifact-and-compose')
                self.assertFalse(any('run' in command or 'up' in command for command in calls))


if __name__ == '__main__':
    unittest.main()
