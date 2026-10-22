import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("web_assets", ROOT / "scripts/prepare-web-assets.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WebAssetsTests(unittest.TestCase):
    def test_current_manifest_preserves_fonts_and_images_without_game_docs(self):
        text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8-sig")
        plan = module.plan(text)
        self.assertTrue(any(path.endswith(".ttf") for path in plan["paths"]))
        self.assertIn("branding/app_icon.png", plan["paths"])
        self.assertTrue(any("/images/" in path for path in plan["paths"]))
        self.assertNotIn("/docs/", plan["manifest"])
        self.assertNotIn(".pdf", plan["manifest"])
        self.assertEqual(module.plan(plan["manifest"]), plan)

    def test_broad_directories_and_web_documents_fail_instead_of_shipping(self):
        for path in ("assets/games/", "assets/games/sample/", "assets/games/sample/docs/", "assets/a.pdf"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                module.plan(f"flutter:\n  assets:\n    - assets/catalog.json\n    - {path}\n")

    def test_native_declarations_are_removed_only_in_deployment_copy(self):
        text = "flutter:\n  assets:\n    - assets/catalog.json\n    - path: assets/games/sample/docs/rules.pdf\n      platforms: [windows, android]\n"
        result = module.plan(text)
        self.assertEqual(result["paths"], ["assets/catalog.json"])
        self.assertIn("rules.pdf", text)
        self.assertNotIn("rules.pdf", result["manifest"])
