"""Check release updates don't leave half-written pins after a network failure."""
import importlib.util
import base64
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("update_inference", REPO / "pkgs/update-inference/update.py")
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class InferenceUpdateTests(unittest.TestCase):
    def test_selects_desktop_release_among_unrelated_products_and_updates_pins(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            pins = root / "pkgs/inference-tools/pins.json"
            pins.parent.mkdir(parents=True)
            pins.write_text('{}\n')
            flake = root / "flake.nix"
            flake.write_text('hermes-agent.url = "github:NousResearch/hermes-agent/v0.1.0";\n')
            proxy_asset = "private-ai-proxy-cli-0.8.5-linux-x64.tar.gz"

            def release(tag, asset):
                return {"tag_name": tag, "assets": [{"name": asset,
                        "browser_download_url": f"https://example.invalid/{asset}"}]}

            def fetch(url, target):
                if "CLIProxyAPI/releases/latest" in url:
                    data = release("v8.0.72", "CLIProxyAPI_8.0.72_linux_amd64.tar.gz")
                elif "private-ai-gateway/releases?" in url:
                    data = [
                        {"tag_name": "clients-v0.11.1", "assets": []},
                        release("desktop-v0.9.0", proxy_asset) | {"prerelease": True},
                        release("desktop-v0.9.0", proxy_asset) | {"draft": True},
                        {"tag_name": "gateway-prod-2026-11-05-2", "assets": []},
                        release("desktop-v0.8.5", proxy_asset),
                    ]
                elif "hermes-agent/releases/latest" in url:
                    data = {"tag_name": "v0.23.1"}
                else:
                    target.write_bytes(b"release archive")
                    return
                target.write_text(json.dumps(data))

            with patch.object(updater, "fetch", side_effect=fetch):
                updater.main(root)
            result = json.loads(pins.read_text())
            self.assertEqual(result["private-ai-proxy"], {
                "version": "0.8.5", "url": f"https://example.invalid/{proxy_asset}",
                "hash": "sha256-" + base64.b64encode(hashlib.sha256(b"release archive").digest()).decode(),
            })
            self.assertEqual(result["cliproxyapi"]["version"], "8.0.72")
            self.assertIn("hermes-agent/v0.23.1", flake.read_text())

    def test_desktop_release_lookup_paginates(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "release.json"
            desktop = {"tag_name": "desktop-v0.8.5", "assets": []}

            def fetch(url, target):
                target.write_text(json.dumps([desktop] if url.endswith("page=2") else [
                    {"tag_name": "clients-v0.11.1", "assets": []}]))

            with patch.object(updater, "fetch", side_effect=fetch) as mocked:
                self.assertEqual(updater.latest_desktop_release("owner/repo", target), desktop)
            self.assertEqual(mocked.call_count, 2)

    def test_no_desktop_release_fails_explicitly(self):
        with tempfile.TemporaryDirectory() as temp:
            def fetch(url, target):
                target.write_text("[]")

            with patch.object(updater, "fetch", side_effect=fetch):
                with self.assertRaisesRegex(ValueError, "Could not find a stable"):
                    updater.latest_desktop_release("owner/repo", Path(temp) / "release.json")

    def test_failed_asset_fetch_preserves_both_pin_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            pins = root / "pkgs/inference-tools/pins.json"
            pins.parent.mkdir(parents=True)
            pins.write_text('{"original": true}\n')
            flake = root / "flake.nix"
            flake.write_text('hermes-agent.url = "github:NousResearch/hermes-agent/v0.1.0";\n')
            original = (pins.read_bytes(), flake.read_bytes())

            def fetch(url, target):
                if url.endswith("releases/latest"):
                    target.write_text(json.dumps({"tag_name": "v8.0.56", "assets": [{
                        "name": "CLIProxyAPI_8.0.56_linux_amd64.tar.gz",
                        "browser_download_url": "https://example.invalid/asset.tar.gz",
                    }]}))
                else:
                    raise OSError("download interrupted")

            with patch.object(updater, "fetch", side_effect=fetch):
                with self.assertRaises(OSError):
                    updater.main(root)
            self.assertEqual((pins.read_bytes(), flake.read_bytes()), original)


if __name__ == "__main__":
    unittest.main()
