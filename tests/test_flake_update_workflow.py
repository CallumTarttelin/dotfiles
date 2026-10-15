"""Exercise the update workflow against a local Git remote and a fake Forgejo API."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


WORKFLOW = Path(__file__).resolve().parents[1] / ".forgejo/workflows/update.yml"
SCRIPT = textwrap.dedent(WORKFLOW.read_text().split(
    "      - name: Create or update PR with auto-merge\n", 1
)[1].split("        run: |\n", 1)[1])


class FlakeUpdateWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "--bare", str(self.root / "remote.git"))
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("remote", "add", "origin", str(self.root / "remote.git"))
        (self.repo / "flake.lock").write_text("old lock\n")
        self.git("add", ".")
        self.git("commit", "-m", "Initial")
        self.git("push", "origin", "main")
        # A failed daily update has left a remote branch and an open PR.
        self.git("checkout", "-b", "auto/flake-update")
        (self.repo / "flake.lock").write_text("yesterday's lock\n")
        self.git("commit", "-am", "Previous update")
        self.git("push", "origin", "auto/flake-update")
        self.git("checkout", "main")
        self.git("branch", "-D", "auto/flake-update")
        (self.repo / "flake.lock").write_text("new lock\n")

        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        curl = bin_dir / "curl"
        curl.write_text("#!/usr/bin/env python3\n" + textwrap.dedent('''
            import json, os, sys
            from urllib.parse import urlparse, parse_qs
            args = sys.argv[1:]
            method = args[args.index("-X") + 1] if "-X" in args else "GET"
            url = next(arg for arg in args if arg.startswith("https://"))
            payload = json.loads(args[args.index("-d") + 1]) if "-d" in args else None
            with open(os.environ["API_LOG"], "a") as log:
                log.write(json.dumps([method, url, payload]) + "\\n")
            exists = os.environ["EXISTING_PR"] == "yes"
            if method == "GET":
                if os.environ.get("LOOKUP_FAILURE"):
                    sys.exit(22)
                query = parse_qs(urlparse(url).query)
                matches = query.get("head") == ["auto/flake-update"]
                print(json.dumps([{"number": 195}] if exists and matches else []))
            elif method == "POST" and exists:
                sys.exit(22)  # Forgejo's 409 when this branch already has a PR.
            else:
                print(json.dumps({"number": 195}))
        '''))
        curl.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                        FLAKE_UPDATER_TOKEN="test-token", EXISTING_PR="yes",
                        API="https://forgejo.invalid/api/v1/repos/owner/dotfiles",
                        API_LOG=str(self.root / "api.log"))

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True,
                              capture_output=True, text=True).stdout.strip()

    def run_update(self):
        return subprocess.run(["bash", "-c", SCRIPT], cwd=self.repo,
                              env=self.env, capture_output=True, text=True)

    def test_refreshes_existing_pr_and_replaces_previous_branch(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in (self.root / "api.log").read_text().splitlines()]
        self.assertEqual([call[0] for call in calls], ["GET", "PATCH"])
        self.assertTrue(calls[1][1].endswith("/pulls/195"))
        self.assertNotIn("state", calls[1][2])
        self.assertEqual(self.git("show", "origin/auto/flake-update:flake.lock"), "new lock")
        self.assertEqual(self.git("rev-parse", "HEAD^"), self.git("rev-parse", "main"))

    def test_creates_pr_when_none_exists(self):
        self.env["EXISTING_PR"] = "no"
        self.git("push", "origin", "--delete", "auto/flake-update")
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in (self.root / "api.log").read_text().splitlines()]
        self.assertEqual([call[0] for call in calls], ["GET", "POST"])
        self.assertEqual(calls[1][2]["head"], "auto/flake-update")
        self.assertEqual(calls[1][2]["base"], "main")

    def test_lookup_failure_stops_before_changing_remote_branch(self):
        self.env["LOOKUP_FAILURE"] = "yes"
        previous = self.git("rev-parse", "origin/auto/flake-update")
        result = self.run_update()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("rev-parse", "origin/auto/flake-update"), previous)
        self.assertEqual(self.git("branch", "--show-current"), "main")


if __name__ == "__main__":
    unittest.main()
