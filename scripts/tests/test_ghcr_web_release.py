import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ghcr_web", ROOT / "scripts/ghcr_web_release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class GhcrWebTests(unittest.TestCase):
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
