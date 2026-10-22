"""Exercise the packaging wrapper with a fake publisher in a temporary project."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == 'nt' and shutil.which('pwsh'), 'Windows PowerShell integration')
class NativePackageEntryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / 'project'
        (self.project / 'scripts').mkdir(parents=True)
        self.release = self.project / 'release'
        self.release.mkdir()
        for name in ('package-app-release.ps1', 'release_retention.py'):
            shutil.copyfile(SCRIPTS / name, self.project / 'scripts' / name)
        self.profiles = self.project / 'profiles'
        self.profiles.mkdir()
        self.profile = self.profiles / 'test.json'
        self.profile.write_text(json.dumps({'projectDir': str(self.project), 'releaseDir': 'release'}))
        self.bin = self.project / 'fake-bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        for build in (1, 2):
            package = self.release / f'board_game_agent-4.1.0+{build}.apk'
            package.write_bytes(f'test-only-{build}'.encode())
            package.with_suffix('.release.json').write_text(json.dumps({
                'appId': 'board_game_agent', 'versionName': '4.1.0', 'buildNumber': build,
                'artifacts': [{'platform': 'android', 'path': package.name,
                               'size': package.stat().st_size,
                               'sha256': hashlib.sha256(package.read_bytes()).hexdigest()}]}))

    def run_entry(self, exit_code):
        (self.bin / 'dart.cmd').write_text(f'@echo off\r\nexit /b {exit_code}\r\n')
        return subprocess.run(['pwsh', '-NoProfile', '-File', str(self.project / 'scripts/package-app-release.ps1'),
                               '-Target', 'android', '-ProfilesDirectory', str(self.profiles),
                               '-PublisherRoot', str(self.project)], env=self.env, capture_output=True,
                              text=True, timeout=20, creationflags=subprocess.CREATE_NO_WINDOW)

    def test_successful_package_runs_targeted_retention(self):
        result = self.run_entry(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.release / 'board_game_agent-4.1.0+1.apk').exists())
        self.assertTrue((self.release / 'board_game_agent-4.1.0+2.apk').exists())

    def test_failed_publisher_does_not_cleanup_previous_packages(self):
        result = self.run_entry(7)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(len(list(self.release.iterdir())), 4)

    def test_other_project_profile_stops_before_publisher_or_cleanup(self):
        self.profile.write_text(json.dumps({'projectDir': str(self.project / 'other'), 'releaseDir': 'release'}))
        result = self.run_entry(0)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(list(self.release.iterdir())), 4)


if __name__ == '__main__':
    unittest.main()
