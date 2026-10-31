import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ghcr_web", ROOT / "scripts/ghcr_web_release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class GhcrWebTests(unittest.TestCase):
    def test_relay_inputs_ignore_web_edits_and_include_dependency_and_base_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in release.AI_INPUTS:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((ROOT / name).read_bytes())
            before = release.ai_input_digest(root)
            (root / "web").mkdir()
            (root / "web/index.html").write_text("unrelated Web edit")
            self.assertEqual(release.ai_input_digest(root), before)
            dockerfile = root / "packaging/docker/Dockerfile.ai"
            dockerfile.write_bytes(dockerfile.read_bytes() + b"\n# a new base or build input\n")
            self.assertNotEqual(release.ai_input_digest(root), before)
            (root / "services/web_account/requirements.txt").write_text("httpx==0.0.1\n")
            with self.assertRaisesRegex(ValueError, "dependency lock"):
                release.ai_input_digest(root)

    def test_registry_miss_and_denied_access_are_different(self):
        image = "ghcr.io/example/board-game-agent-web-ai:inputs-" + "a" * 64
        for status in (404, 403):
            token = io.BytesIO(b'{"token":"fixture"}')
            failure = urllib.error.HTTPError("https://ghcr.io", status, "fixture", {}, None)
            with patch.object(release.urllib.request, "urlopen", side_effect=[token, failure]):
                if status == 404:
                    self.assertFalse(release.ai_image_exists(image))
                else:
                    with self.assertRaisesRegex(RuntimeError, "403"):
                        release.ai_image_exists(image)
        response = MagicMock()
        response.__enter__.return_value.status = 200
        with patch.object(release.urllib.request, "urlopen", side_effect=[io.BytesIO(b'{"token":"fixture"}'), response]):
            self.assertTrue(release.ai_image_exists(image))

    def test_compose_has_new_ports_and_no_old_nas_data_dependencies(self):
        text = release.compose("ghcr.io/example/board-game-agent:5.0.0-54-test", "ghcr.io/example/board-game-agent-web-ai:5.0.0-54-test")
        document = release.yaml.safe_load(text)
        self.assertEqual(document["services"]["board-game-agent"]["ports"], ["8083:8080"])
        self.assertEqual(document["services"]["web-ai"]["environment"]["WEB_PUBLIC_ORIGIN"], "https://cznas.pp.ua:8084")
        self.assertNotIn("18887", text)
        self.assertNotIn("web-account", text)
        self.assertNotIn("volumes", text)
        self.assertNotIn("${", text)
        self.assertNotIn("build:", text)

    def test_reusable_nas_compose_tracks_both_images_without_changing_ports(self):
        text = release.nas_compose()
        document = release.yaml.safe_load(text)
        services = document["services"]
        self.assertEqual(services["board-game-agent"]["image"], "ghcr.io/chenxuanjie/board-game-agent:nas")
        self.assertEqual(services["web-ai"]["image"], "ghcr.io/chenxuanjie/board-game-agent-web-ai:nas")
        self.assertTrue(all(service["pull_policy"] == "always" for service in services.values()))
        self.assertEqual(services["board-game-agent"]["ports"], ["8083:8080"])
        self.assertNotIn("volumes:", text)

    def test_archive_escape_and_incomplete_snapshots_are_rejected(self):
        for path in ("../private", "/private", "shared_packages/example/lib/value.dart"):
            packed = io.BytesIO()
            with tarfile.open(fileobj=packed, mode="w") as archive:
                item = tarfile.TarInfo(path)
                item.size = 1
                archive.addfile(item, io.BytesIO(b"x"))
            with tempfile.TemporaryDirectory() as directory:
                with tarfile.open(fileobj=io.BytesIO(packed.getvalue())) as archive:
                    with self.assertRaises(ValueError):
                        release.extract(archive, Path(directory), {})

    def test_snapshot_hashes_match_every_archived_dependency(self):
        record = json.loads((ROOT / release.LOCK).read_text(encoding="utf-8"))
        packed = (ROOT / release.SNAPSHOT).read_bytes()
        self.assertEqual(record["archiveSha256"], release.digest(packed))
        self.assertTrue(all(len(item["commit"]) == 40 for item in record["packages"]))
        with tempfile.TemporaryDirectory() as directory:
            with tarfile.open(fileobj=io.BytesIO(packed), mode="r:gz") as archive:
                release.extract(archive, Path(directory), record["files"])

    def test_metadata_is_scoped_to_the_requested_owner_and_commit(self):
        record = release.metadata("Example/board-game-agent", "a" * 40, "codex/board-service-business")
        self.assertEqual(record["webImage"].split(":")[0], "ghcr.io/example/board-game-agent")
        self.assertTrue(record["webImage"].endswith("-aaaaaaaaaaaa"))
        self.assertEqual(record["branchTag"], "branch-codex-board-service-business")
        with self.assertRaises(ValueError):
            release.metadata("example/board-game-agent", "HEAD", "main")
