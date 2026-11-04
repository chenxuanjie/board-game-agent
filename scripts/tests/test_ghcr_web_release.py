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
    def test_registry_rejects_a_frozen_dependency_or_version_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "packaging/ci").mkdir(parents=True)
            (root / "pubspec.yaml").write_text("name: board_game_agent\nversion: 5.0.1+56\n")
            descriptor = {"schemaVersion": 1, "appId": "board_game_agent", "batchId": "00000000-0000-4000-8000-000000000001", "versionName": "5.0.1", "buildNumber": 56}
            (root / "release-batch.json").write_text(json.dumps(descriptor))
            (root / release.LOCK).write_text(json.dumps({"packages": [{"name": "app_client", "commit": "b" * 40}]}))
            frozen = {**descriptor, "state": "frozen", "sourceRevision": "a" * 40, "dependencyRevisions": {"app_client": "b" * 40}}
            def git(_, *args):
                return "" if args[0] == "status" else "a" * 40
            with patch.object(release, "git", side_effect=git), patch.object(release, "registry_request", return_value=frozen):
                self.assertEqual(release.verify_batch(root)["buildNumber"], 56)
                frozen["dependencyRevisions"] = {"app_client": "c" * 40}
                with self.assertRaisesRegex(ValueError, "dependencies"):
                    release.verify_batch(root)
                (root / "pubspec.yaml").write_text("version: 5.0.1+57\n")
                with self.assertRaisesRegex(ValueError, "version differ"):
                    release.verify_batch(root)

    def test_registry_image_registration_preserves_the_reused_proxy_source(self):
        batch = {"batchId": "00000000-0000-4000-8000-000000000001", "versionName": "5.0.1", "buildNumber": 56, "sourceRevision": "a" * 40}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release.json"
            path.write_text(json.dumps({"dirtySource": False, "sourceRevision": "a" * 40, "applicationVersion": "5.0.1+56", "images": {
                "web": {"reference": "ghcr.io/example/web@sha256:" + "c" * 64, "sourceRevision": "a" * 40},
                "webAi": {"reference": "ghcr.io/example/relay@sha256:" + "d" * 64, "sourceRevision": "b" * 40, "reused": True, "inputDigest": "e" * 64}}}))
            with patch.object(release, "verify_batch", return_value=batch), patch.object(release, "registry_request", return_value={}) as request:
                release.register_images(path, "published")
                records = [call.args[2] for call in request.call_args_list]
                self.assertEqual([record["sourceRevision"] for record in records], ["a" * 40, "b" * 40])
                self.assertTrue(records[1]["reused"])
                retry = json.loads(path.read_text())
                retry["images"]["webAi"].update(sourceRevision="a" * 40, reused=True)
                path.write_text(json.dumps(retry))
                release.register_images(path, "published")
                self.assertFalse(request.call_args.args[2]["reused"])

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
        services = document['services']
        self.assertEqual(set(services), {'board-game-agent', 'web-ai'})
        self.assertNotIn('ports', services['web-ai'])
        self.assertEqual(services['board-game-agent']['environment']['APP_SERVICE_UPSTREAM'],
                         'http://192.168.1.55:18280')
        nginx = (ROOT / 'packaging/docker/nginx.conf').read_text()
        self.assertIn('http://web-ai:8000', nginx)
        self.assertIn('proxy_pass ${APP_SERVICE_UPSTREAM}/;', nginx)
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
