"""Opt-in real Gradle signing checks, with no app compilation or private keys.

Run with BGA_ANDROID_SIGNING_GRADLE_TESTS=1. The fixture copies build scripts,
SDK locations and a minimal Flutter manifest, never android/key.properties or
the real keystore. Gradle uses installed dependencies offline.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
ENABLED = os.environ.get("BGA_ANDROID_SIGNING_GRADLE_TESTS") == "1"


@unittest.skipUnless(ENABLED, "Opt in with BGA_ANDROID_SIGNING_GRADLE_TESTS=1")
class AndroidSigningGradleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="bga-signing-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.project = Path(cls.temp.name)
        cls.android = cls.project / "android"
        cls.app = cls.android / "app"
        cls.app.mkdir(parents=True)
        for name in ("build.gradle.kts", "settings.gradle.kts", "gradlew", "gradlew.bat"):
            shutil.copyfile(ROOT / "android" / name, cls.android / name)
        shutil.copytree(ROOT / "android/gradle", cls.android / "gradle")
        shutil.copyfile(ROOT / "android/app/build.gradle.kts", cls.app / "build.gradle.kts")
        locations = (ROOT / "android/local.properties").read_text(encoding="utf-8")
        cls.android.joinpath("local.properties").write_text(
            "\n".join(line for line in locations.splitlines()
                      if line.startswith(("sdk.dir=", "flutter.sdk="))) + "\n",
            encoding="utf-8",
        )
        cls.android.joinpath("gradle.properties").write_text(
            "org.gradle.jvmargs=-Xmx2G\nandroid.useAndroidX=true\n",
            encoding="utf-8",
        )
        cls.project.joinpath("pubspec.yaml").write_text(
            "name: signing_fixture\nversion: 1.0.0+1\n"
            "environment:\n  sdk: '>=3.0.0 <4.0.0'\n"
            "dependencies:\n  flutter:\n    sdk: flutter\n",
            encoding="utf-8",
        )
        manifest = cls.app / "src/main/AndroidManifest.xml"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:label="Signing fixture"/></manifest>',
            encoding="utf-8",
        )
        # Inspect the effective AGP model, not source strings alone.
        cls.inspect = cls.project / "inspect.gradle"
        cls.inspect.write_text("""
gradle.projectsEvaluated {
    def app = gradle.rootProject.findProject(':app')
    if (app == null) return // Flutter's included Gradle tooling build is separate.
    def android = app.extensions.getByName('android')
    app.tasks.register('inspectSigningPolicy') {
        doLast {
            assert android.buildTypes.getByName('debug').signingConfig.name == 'debug'
            assert android.buildTypes.getByName('release').signingConfig.name == 'release'
            assert !android.buildTypes.getByName('release').debuggable
            println 'F07_SIGNING_POLICY_OK'
        }
    }
}
""", encoding="utf-8")
        cls.key = cls.android / "key.properties"
        cls.keystore = cls.android / "fixture.jks"
        keytool = shutil.which("keytool")
        if keytool is None:
            raise RuntimeError("Installed JDK keytool is required")
        generated = subprocess.run(
            [keytool, "-genkeypair", "-alias", "fixture", "-keystore", str(cls.keystore),
             "-storepass", "fixture-only-password", "-keypass", "fixture-only-password",
             "-keyalg", "RSA", "-keysize", "2048", "-validity", "1",
             "-dname", "CN=Disposable Signing Test", "-noprompt"],
            capture_output=True, text=True, timeout=30,
        )
        if generated.returncode:
            raise RuntimeError("Could not generate disposable signing fixture")

    def setUp(self):
        self.key.unlink(missing_ok=True)

    def valid_properties(self, **overrides):
        values = dict(storeFile="fixture.jks", storePassword="fixture-only-password",
                      keyAlias="fixture", keyPassword="fixture-only-password")
        values.update(overrides)
        self.key.write_text("\n".join(f"{key}={value}" for key, value in values.items()) + "\n",
                            encoding="utf-8")

    def gradle(self, *tasks, success=True):
        wrapper = self.android / ("gradlew.bat" if os.name == "nt" else "gradlew")
        command = [str(wrapper), "--offline", "--no-daemon", "--console=plain",
                   "-I", str(self.inspect), *tasks]
        result = subprocess.run(command, cwd=self.android, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=240)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(list(self.project.rglob("*.apk")))
        self.assertFalse(list(self.project.rglob("*.aab")))
        return result.stdout + result.stderr

    def test_missing_release_file_allows_debug_and_project_configuration(self):
        output = self.gradle("help", ":app:preDebugBuild", ":app:inspectSigningPolicy")
        self.assertIn("F07_SIGNING_POLICY_OK", output)

    def test_missing_release_file_blocks_release_signing(self):
        # AGP omits validateSigningRelease when credentials are incomplete.
        # The Release prebuild gate must still block unsigned output.
        output = self.gradle(":app:preReleaseBuild", success=False)
        self.assertIn("Release signing requires android/key.properties", output)

    def test_partial_release_configuration_allows_debug(self):
        self.key.write_text("keyAlias=fixture\n", encoding="utf-8")
        output = self.gradle(":app:preDebugBuild", ":app:inspectSigningPolicy")
        self.assertIn("F07_SIGNING_POLICY_OK", output)

    def test_blank_release_credentials_block_before_release_prebuild(self):
        self.valid_properties(keyPassword="")
        output = self.gradle(":app:preReleaseBuild", success=False)
        self.assertIn("Release signing is missing fields: keyPassword", output)

    def test_malformed_properties_allow_debug_but_block_release(self):
        self.key.write_text(r"keyAlias=\uZZZZ" + "\n", encoding="utf-8")
        self.gradle(":app:preDebugBuild", ":app:inspectSigningPolicy")
        output = self.gradle(":app:preReleaseBuild", success=False)
        self.assertIn("Release signing could not read android/key.properties", output)

    def test_missing_keystore_is_release_only_failure(self):
        self.valid_properties(storeFile="missing.jks")
        self.gradle(":app:preDebugBuild")
        output = self.gradle(":app:validateSigningRelease", success=False)
        self.assertIn("Release signing keystore is missing or invalid", output)

    def test_valid_private_configuration_passes_both_signing_models(self):
        self.valid_properties()
        output = self.gradle(":app:preDebugBuild", ":app:validateSigningRelease",
                             ":app:inspectSigningPolicy")
        self.assertIn("F07_SIGNING_POLICY_OK", output)

    def test_abbreviated_and_aggregate_release_graphs_keep_the_gate(self):
        for tasks in [(":app:aR",), (":app:assemble",), (":app:bundleRelease",),
                      (":app:preDebugBuild", ":app:assembleRelease")]:
            with self.subTest(tasks=tasks):
                output = self.gradle(*tasks, "--dry-run")
                self.assertIn(":app:validateReleaseSigningConfiguration SKIPPED", output)
                self.assertIn(":app:preReleaseBuild SKIPPED", output)


if __name__ == "__main__":
    unittest.main()
