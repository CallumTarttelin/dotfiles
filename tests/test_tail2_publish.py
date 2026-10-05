"""Check peer-map refreshes without touching host routes, secrets, or firewall."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


MODULE = Path(__file__).resolve().parents[1] / "modules/features/multi-tailnet.nix"
SCRIPT = textwrap.dedent(MODULE.read_text().split("<<'PY'\n", 1)[1].split("\n      PY", 1)[0])


def peer(ip, name):
    return {"TailscaleIPs": [ip], "DNSName": name}


class Tail2PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, TAIL2_NAMESPACE="tail2",
                        TAIL2_NAMESPACE_VETH="veth-tail2-ns",
                        TAIL2_TAILSCALE_INTERFACE="tailscale0",
                        TAIL2_VETH_SUBNET="192.168.101.0/24")

    def publish(self, peers, hosts, primary_peers=None):
        values = {
            "config": {"hosts": hosts},
            "primary": {"Peer": primary_peers or {}},
            "secondary": {"BackendState": "Running",
                          "Self": peer("100.64.0.1", "self.secondary.ts.net."),
                          "Peer": peers},
        }
        for name, value in values.items():
            (self.root / name).write_text(json.dumps(value))
        return subprocess.run(
            [sys.executable, "-", *(str(self.root / name) for name in values), str(self.root)],
            input=SCRIPT, env=self.env, capture_output=True, text=True,
        )

    def test_missing_peer_is_omitted_then_published_when_it_returns(self):
        hosts = {"devbox": {"target": "dev", "user": "developer"},
                 "available": {"target": "other"}}
        peers = {"other": peer("100.64.0.2", "other.secondary.ts.net.")}
        result = self.publish(peers, hosts)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("skipping manual alias 'devbox'", result.stderr)
        self.assertNotIn("devbox", (self.root / "hosts.block").read_text())
        self.assertIn("Host available", (self.root / "ssh_config").read_text())
        self.assertEqual((self.root / "routes.desired").read_text(), "100.64.0.2\n")

        peers["dev"] = peer("100.64.0.3", "dev.secondary.ts.net.")
        result = self.publish(peers, hosts)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("devbox", (self.root / "hosts.block").read_text())
        self.assertIn("Host devbox\n  HostName 100.64.0.3\n  User developer",
                      (self.root / "ssh_config").read_text())

        result = self.publish({}, hosts)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ("hosts.block", "ssh_config", "routes.desired"):
            self.assertEqual((self.root / name).read_text(), "")

    def test_ambiguous_peer_names_still_fail(self):
        peers = {"a": peer("100.64.0.2", "dev.one.ts.net."),
                 "b": peer("100.64.0.3", "dev.two.ts.net.")}
        result = self.publish(peers, {"devbox": {"target": "dev"}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("maps to both", result.stderr)

    def test_primary_alias_collision_still_fails(self):
        result = self.publish({}, {"devbox": {"target": "dev"}},
                              {"primary": peer("100.64.1.1", "devbox.primary.ts.net.")})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("collides with primary tailnet name", result.stderr)


if __name__ == "__main__":
    unittest.main()
