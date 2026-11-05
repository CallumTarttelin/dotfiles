"""Check release updates don't leave half-written pins after a network failure."""
import importlib.util
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
