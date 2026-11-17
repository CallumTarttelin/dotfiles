"""Exercise AppImage release selection and pin updates without network access."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SCRIPT = (REPO / "pkgs/update-t3code/default.nix").read_text().split("  text = ''\n", 1)[1].rsplit("  '';", 1)[0].replace("''${", "${").replace("${flake}", "/nonexistent")


class T3CodeUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.package = self.root / "pkgs/t3code/default.nix"
        self.package.parent.mkdir(parents=True)
        self.original = (REPO / "pkgs/t3code/default.nix").read_text()
        self.package.write_text(self.original)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for name, script in {
            "curl": '#!/bin/sh\ncat "$RELEASE_JSON"\n',
            "nix": '#!/bin/sh\nprintf "%s\\n" "$*" >> "$PREFETCH_LOG"\nprintf \'{"hash":"sha256-test="}\\n\'\n',
        }.items():
            executable = bin_dir / name
            executable.write_text(script)
            executable.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                        RELEASE_JSON=str(self.root / "release.json"),
                        PREFETCH_LOG=str(self.root / "prefetch.log"))

    def update(self, names):
        release = {"tag_name": "v0.1.10", "assets": [
            {"name": name, "browser_download_url": f"https://example.invalid/{name}"}
            for name in names
        ]}
        (self.root / "release.json").write_text(json.dumps(release))
        return subprocess.run(["bash", "-c", SCRIPT], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def test_updates_version_hash_and_asset_for_both_naming_schemes(self):
        for asset in ["T3-Code-x86_64.AppImage", "T3-Code-0.1.10-x86_64.AppImage"]:
            with self.subTest(asset=asset):
                result = self.update(["T3-Code-arm64.AppImage", asset])
                self.assertEqual(result.returncode, 0, result.stderr)
                package = self.package.read_text()
                self.assertIn('version = "0.1.10";', package)
                self.assertIn('hash = "sha256-test=";', package)
                self.assertIn(f'assetName = "{asset}";', package)
                self.assertIn(f"https://example.invalid/{asset}", (self.root / "prefetch.log").read_text())

    def test_prefers_new_name_when_both_are_present(self):
        result = self.update(["T3-Code-0.1.10-x86_64.AppImage", "T3-Code-x86_64.AppImage"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('assetName = "T3-Code-x86_64.AppImage";', self.package.read_text())

    def test_missing_x86_64_asset_leaves_pin_unchanged(self):
        result = self.update(["T3-Code-arm64.AppImage"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not find an x86_64 AppImage", result.stderr)
        self.assertEqual(self.package.read_text(), self.original)
        self.assertFalse((self.root / "prefetch.log").exists())


if __name__ == "__main__":
    unittest.main()
