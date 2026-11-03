import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("ghcr_delivery", ROOT / "scripts/write-ghcr-delivery.py")
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)


class GhcrDeliveryTests(unittest.TestCase):
    def test_reused_relay_keeps_its_own_source_commit_and_validates_inputs(self):
        image = "ghcr.io/example/relay:inputs-" + "c" * 64
        data = {"Os": "linux", "Architecture": "amd64", "Id": "sha256:" + "d" * 64,
                "RepoDigests": ["ghcr.io/example/relay@sha256:" + "e" * 64],
                "Config": {"Labels": {"org.opencontainers.image.revision": "b" * 40,
                                       "io.board-game-agent.build-inputs": "c" * 64}}}
        with patch.object(delivery, "ai_input_digest", return_value="c" * 64), \
                patch.object(delivery, "git", return_value="a" * 40), \
                patch.object(delivery.subprocess, "check_output", side_effect=lambda *a, **k: json.dumps([data])):
            record = delivery.published(image, relay=True, reused=True)
            self.assertEqual(record["sourceRevision"], "b" * 40)
            self.assertTrue(record["reused"])
            with self.assertRaisesRegex(ValueError, "source differs"):
                delivery.published(image, relay=True)
            data["Config"]["Labels"]["io.board-game-agent.build-inputs"] = "0" * 64
            with self.assertRaisesRegex(ValueError, "source inputs"):
                delivery.published(image, relay=True, reused=True)
