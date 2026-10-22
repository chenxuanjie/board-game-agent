"""Retention tests use tiny temporary fixtures, never real release files."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
import tarfile
from docker_fixtures import write_image_archive

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_retention as retention


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'release'
        self.root.mkdir()

    def native(self, platform, build):
        version = f'4.1.0+{build}'
        suffix = '.apk' if platform == 'android' else '-windows-x64-setup.exe'
        file = self.root / f'board_game_agent-{version}{suffix}'
        file.write_bytes(f'test-only-{platform}-{build}'.encode())
        artifact = {'platform': platform, 'path': 'apps/test/' + file.name,
                    'size': file.stat().st_size, 'sha256': retention.digest(file)}
        value = {'appId': 'board_game_agent', 'versionName': '4.1.0', 'buildNumber': build,
                 'artifacts': [artifact]}
        record = self.root / f'board_game_agent-{version}{"-windows" if platform == "windows" else ""}.release.json'
        record.write_text(json.dumps(value))
        if platform == 'windows':
            manifest = dict(value, artifacts=[dict(artifact, path=file.name)])
            (self.root / 'board_game_agent-windows-x64-manifest.json').write_text(json.dumps(manifest))
        return file, record

    def docker(self, build, arch='amd64', legacy=False):
        filename = (f'board-game-agent-test-{build}-linux-{arch}-images.tar' if legacy
                    else f'board-game-agent-linux-{arch}-images.tar')
        archive = self.root / filename
        write_image_archive(archive, [f'board-game-agent:test-{build}', f'board-game-agent-web-account:test-{build}'], arch)
        if not legacy:
            reports = self.root / 'reports' / f'docker-linux-{arch}'
            reports.mkdir(parents=True, exist_ok=True)
            (reports / 'release.json').write_text(json.dumps({'artifact': {
                'fileName': filename, 'size': archive.stat().st_size, 'sha256': retention.digest(archive)}}))
        return archive

    def test_each_native_platform_retains_its_own_complete_latest_version(self):
        self.native('android', 1); latest_apk = self.native('android', 3)
        self.native('windows', 1); latest_exe = self.native('windows', 2)
        result = retention.cleanup(self.root)
        self.assertEqual(len(result['removed']), 4)
        self.assertTrue(all(p.exists() for p in latest_apk + latest_exe))
        self.assertFalse((self.root / 'board_game_agent-4.1.0+1.apk').exists())

    def test_invalid_latest_artifact_retains_all_previous_versions(self):
        old = self.native('android', 1)
        latest, _ = self.native('android', 2)
        latest.write_bytes(b'interrupted-package')
        before = set(self.root.iterdir())
        with self.assertRaisesRegex(ValueError, 'not complete'):
            retention.cleanup(self.root)
        self.assertEqual(set(self.root.iterdir()), before)
        self.assertTrue(all(p.exists() for p in old))

    def test_missing_release_record_does_not_delete_last_good_package(self):
        old = self.native('android', 1)
        (self.root / 'board_game_agent-4.1.0+2.apk').write_bytes(b'partial')
        with self.assertRaises(ValueError):
            retention.cleanup(self.root)
        self.assertTrue(all(p.exists() for p in old))

    def test_all_selected_platforms_validate_before_any_deletion(self):
        old_apk = self.native('android', 1)
        self.native('android', 2)
        old_exe = self.native('windows', 1)
        _, broken = self.native('windows', 2)
        broken.write_text('{}')
        with self.assertRaises(ValueError):
            retention.cleanup(self.root)
        self.assertTrue(all(p.exists() for p in old_apk + old_exe))

    def test_dry_run_has_no_side_effects(self):
        self.native('android', 1); self.native('android', 2)
        self.docker(1, legacy=True); self.docker(2)
        before = {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        result = retention.cleanup(self.root, dry_run=True)
        self.assertGreater(result['freedBytes'], 0)
        self.assertEqual({p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}, before)

    def test_other_projects_and_unknown_files_or_folders_are_preserved(self):
        self.native('android', 1); self.native('android', 2)
        unknown = self.root / 'another-app-1.0.0+1.apk'
        unknown.write_text('keep')
        folder = self.root / 'manual-backups'
        folder.mkdir(); (folder / 'old.zip').write_text('keep')
        retention.cleanup(self.root)
        self.assertEqual(unknown.read_text(), 'keep')
        self.assertEqual((folder / 'old.zip').read_text(), 'keep')

    def test_docker_keeps_one_per_arch_and_moves_latest_reports(self):
        old = self.docker(1, legacy=True)
        current = self.docker(2)
        arm = self.docker(3, 'arm64')
        source = self.root / 'board-game-agent-4.0.0+1-docker.zip'
        source.write_text('obsolete-source-delivery')
        retention.cleanup(self.root, ('docker',))
        self.assertFalse(old.exists()); self.assertFalse(source.exists())
        self.assertTrue(current.exists()); self.assertTrue(arm.exists())
        self.assertTrue((self.root / 'reports/docker-linux-amd64/release.json').exists())

    def test_corrupt_tar_stops_before_deleting_previous_package(self):
        old = self.docker(1, legacy=True)
        current = self.docker(2)
        current.write_bytes(b'broken export')
        with self.assertRaises((ValueError, tarfile.TarError)):
            retention.cleanup(self.root, ('docker',))
        self.assertTrue(old.exists())

    def test_tar_must_match_its_record_before_cleanup(self):
        old = self.docker(1, legacy=True)
        self.docker(2)
        record = self.root / 'reports/docker-linux-amd64/release.json'
        metadata = json.loads(record.read_text())
        metadata['artifact']['sha256'] = '0' * 64
        record.write_text(json.dumps(metadata))
        with self.assertRaisesRegex(ValueError, 'TAR does not match'):
            retention.cleanup(self.root, ('docker',))
        self.assertTrue(old.exists())

    def test_targeted_cleanup_does_not_remove_other_platforms(self):
        old = self.native('windows', 1)
        self.native('windows', 2)
        self.native('android', 1); self.native('android', 2)
        retention.cleanup(self.root, ('android',))
        self.assertTrue(all(p.exists() for p in old))

    def test_symlink_cannot_be_followed_or_deleted(self):
        self.native('android', 2)
        outside = Path(self.temporary.name) / 'outside.apk'
        outside.write_bytes(b'outside')
        link = self.root / 'board_game_agent-4.1.0+1.apk'
        try:
            link.symlink_to(outside)
        except OSError:
            self.skipTest('symlink privilege unavailable')
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            retention.cleanup(self.root, ('android',))
        self.assertEqual(outside.read_bytes(), b'outside')
        self.assertTrue(link.is_symlink())


if __name__ == '__main__':
    unittest.main()
