import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), ROOT / "scripts" / (name + ".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


layers = module("prepare-web-layers")
comparison = module("compare-image-layers")


class WebImageLayersTests(unittest.TestCase):
    def test_partition_preserves_all_bytes_and_only_code_group_changes(self):
        files = {"index.html": b"html", "main.dart.js": b"code", "canvaskit/canvaskit.wasm": b"engine",
                 "powersync/sqlite3.wasm": b"sqlite", "assets/packages/pdfrx/assets/pdfium.wasm": b"pdf",
                 "assets/assets/fonts/font.ttf": b"font", "assets/fonts/MaterialIcons.otf": b"icons",
                 "assets/assets/mobile/home/banner.png": b"image", "assets/FontManifest.json": b"[]"}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "web"
            for name, content in files.items():
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            before = layers.prepare(source, root / "before")
            for name in files:
                os.utime(source / name, (1000000, 1000000))
            repeated = layers.prepare(source, root / "repeated")
            self.assertEqual(before, repeated)
            copied = {}
            for group in layers.GROUPS:
                for name in before[group]["files"]:
                    path = root / "before" / group / name
                    self.assertNotIn(name, copied)
                    copied[name] = path.read_bytes()
                    self.assertEqual(path.stat().st_mtime, 0)
            self.assertEqual(copied, files)
            # Equal-length changes must also change the browser cache validator.
            (source / "main.dart.js").write_bytes(b"CODE")
            after = layers.prepare(source, root / "after")
            self.assertEqual([group for group in layers.GROUPS if before[group] != after[group]], ["app"])
            self.assertNotEqual((root / "before/web-etags.map").read_bytes(), (root / "after/web-etags.map").read_bytes())

    def test_does_not_overwrite_outputs_or_accept_incomplete_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                layers.prepare(root, root / "nested")
            with self.assertRaises(ValueError):
                layers.prepare(root / "missing", root / "result")

    def test_download_is_missing_whole_layers_and_tag_does_not_matter(self):
        base = {"digest": "sha256:base", "size": 100}
        old = {"layers": [base, {"digest": "sha256:old", "size": 90}]}
        new = {"layers": [base, {"digest": "sha256:new", "size": 10}]}
        self.assertEqual(comparison.compare(old, new)["downloadBytes"], 10)
        self.assertEqual(comparison.compare(new, new)["downloadBytes"], 0)
        self.assertEqual(comparison.compare({"layers": []}, new)["downloadBytes"], 110)
