"""Run the NAS shell flow with fake Docker/uname; never contacts a Docker host."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.name == "posix", "Execute this suite on Linux/WSL for POSIX shell coverage")
class NasDeployTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "bin").mkdir()
        self.log = self.root / "docker-calls.log"
        self.env = dict(os.environ, PATH=str(self.root / "bin") + ":" + os.environ["PATH"], TEST_DEPLOY_LOG=str(self.log))
        self.env.pop("IMAGE_TAG", None)
        self.env.pop("BGA_IMAGE_PLATFORM", None)
        self.env.pop("COMPOSE_PROJECT_NAME", None)
        files = {
            "deploy.sh": (ROOT / "packaging/docker/deploy.sh").read_text(),
            "image-tag.txt": "release-current\n",
            "image-platform.txt": "linux/amd64\n",
            "images.tar": "fake images for test only",
            "docker-compose.yml": "services: {}\n",
        }
        for name, value in files.items():
            (self.root / name).write_text(value)
        (self.root / ".env").write_text("IMAGE_TAG=old-version\nLIBRARY_PATH=/unchanged-library\n")
        sums = "".join(f"{hashlib.sha256((self.root / name).read_bytes()).hexdigest()}  {name}\n" for name in files)
        (self.root / "checksums.sha256").write_text(sums)
        (self.root / "bin/docker").write_text('#!/bin/sh\nprintf "%s|%s|%s\\n" "${IMAGE_TAG:-unset}" "${BGA_IMAGE_PLATFORM:-unset}" "$*" >> "$TEST_DEPLOY_LOG"\n')
        (self.root / "bin/uname").write_text('#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo "${TEST_NAS_CPU:-x86_64}";; esac\n')
        for executable in (self.root / "bin").iterdir():
            executable.chmod(0o700)

    def run_script(self):
        return subprocess.run(["sh", str(self.root / "deploy.sh")], env=self.env, capture_output=True, text=True, timeout=10)

    def test_import_and_start_do_not_use_retained_env(self):
        before = (self.root / ".env").read_bytes()
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text().splitlines()
        self.assertTrue(any('image load --input images.tar' in line for line in calls))
        self.assertFalse(any('--env-file' in line for line in calls))
        self.assertTrue(any("up -d --no-build --pull never" in line for line in calls))
        self.assertTrue(any("-p board-game-agent" in line for line in calls))
        self.assertEqual((self.root / ".env").read_bytes(), before)

    def test_corrupt_archive_cannot_be_loaded(self):
        (self.root / "images.tar").write_text("corrupt")
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertNotIn("image load", self.log.read_text())

    def test_wrong_nas_architecture_cannot_be_loaded(self):
        self.env["TEST_NAS_CPU"] = "aarch64"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("architecture", result.stderr)
        self.assertNotIn("image load", self.log.read_text())

    def test_no_env_file_is_required(self):
        (self.root / ".env").unlink()
        self.assertEqual(self.run_script().returncode, 0)
        self.assertFalse((self.root / '.env').exists())

    def test_missing_compose_does_not_invoke_docker_or_create_defaults(self):
        (self.root / 'docker-compose.yml').unlink()
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.log.exists())
