from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "gcloud_remote_login.py"
SPEC = importlib.util.spec_from_file_location("gcloud_remote_login", MODULE_PATH)
assert SPEC and SPEC.loader
gcloud_remote_login = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gcloud_remote_login
SPEC.loader.exec_module(gcloud_remote_login)


BOOTSTRAP_URL = (
    "https://accounts.google.com/o/oauth2/auth?"
    "client_id=example&state=test-state&token_usage=remote"
)
CALLBACK_URL = "https://localhost:4567/?state=test-state&code=test-code&scope=cloud"


def write_executable(path: pathlib.Path, content: str) -> None:
    path.write_text(textwrap.dedent(content), encoding="utf-8")
    path.chmod(0o755)


def make_remote_path(root: pathlib.Path) -> str:
    bin_dir = root / "remote-path"
    bin_dir.mkdir()
    for command in ("head", "sed", "sh"):
        source = shutil.which(command)
        assert source
        (bin_dir / command).symlink_to(source)
    return str(bin_dir)


class ArgumentTests(unittest.TestCase):
    def test_defaults(self):
        args = gcloud_remote_login.parse_args([])
        self.assertEqual(args.host, "devbox")
        self.assertEqual(args.browser, "firefox-work")
        self.assertEqual(args.timeout, 900.0)
        self.assertFalse(args.force)

    def test_overrides(self):
        args = gcloud_remote_login.parse_args(
            [
                "other-host",
                "--force",
                "--browser",
                "/tmp/browser",
                "--account",
                "user@example.com",
                "--quota-project",
                "quota-project",
                "--remote-gcloud",
                "/opt/gcloud",
                "--timeout",
                "30",
            ]
        )
        self.assertEqual(args.host, "other-host")
        self.assertTrue(args.force)
        self.assertEqual(args.account, "user@example.com")
        self.assertEqual(args.quota_project, "quota-project")
        self.assertEqual(args.remote_gcloud, "/opt/gcloud")
        self.assertEqual(args.timeout, 30.0)

    def test_remote_command_contains_quoted_values(self):
        args = gcloud_remote_login.parse_args(
            ["host", "--account", "user+work@example.com", "--quota-project", "my-project"]
        )
        command = gcloud_remote_login.build_remote_command(args)
        self.assertIn("user+work@example.com", command)
        self.assertIn("my-project", command)
        self.assertIn("--no-browser --update-adc", command)


class UrlTests(unittest.TestCase):
    def test_extracts_unwrapped_bootstrap(self):
        output = f'gcloud auth login --remote-bootstrap="{BOOTSTRAP_URL}"\n'
        self.assertEqual(gcloud_remote_login.extract_bootstrap(output), BOOTSTRAP_URL)

    def test_extracts_wrapped_bootstrap(self):
        wrapped = BOOTSTRAP_URL.replace("&state", "\n    &state")
        output = f'gcloud auth login --remote-bootstrap="{wrapped}"\n'
        self.assertEqual(gcloud_remote_login.extract_bootstrap(output), BOOTSTRAP_URL)

    def test_rejects_untrusted_bootstrap(self):
        url = "https://evil.example/o/oauth2/auth?state=x&token_usage=remote"
        with self.assertRaises(gcloud_remote_login.LoginError):
            gcloud_remote_login.extract_bootstrap(
                f'gcloud auth login --remote-bootstrap="{url}"'
            )

    def test_validates_callback(self):
        self.assertEqual(
            gcloud_remote_login.validate_callback_url(CALLBACK_URL, "test-state"),
            CALLBACK_URL,
        )

    def test_accepts_ipv4_and_ipv6_loopback(self):
        for url in (
            "https://127.0.0.1:1234/?state=test-state&code=code",
            "https://[::1]:1234/?state=test-state&code=code",
        ):
            with self.subTest(url=url):
                self.assertEqual(
                    gcloud_remote_login.validate_callback_url(url, "test-state"), url
                )

    def test_rejects_callback_without_code(self):
        with self.assertRaises(gcloud_remote_login.LoginError):
            gcloud_remote_login.validate_callback_url(
                "https://localhost:1234/?state=test-state", "test-state"
            )

    def test_rejects_mismatched_state(self):
        with self.assertRaises(gcloud_remote_login.LoginError):
            gcloud_remote_login.validate_callback_url(CALLBACK_URL, "other-state")

    def test_redacts_oauth_values(self):
        text = (
            f'gcloud auth login --remote-bootstrap="{BOOTSTRAP_URL}"\n'
            f"callback: {CALLBACK_URL}\n"
        )
        redacted = gcloud_remote_login.redact(text)
        self.assertNotIn("test-state", redacted)
        self.assertNotIn("test-code", redacted)
        self.assertNotIn("accounts.google.com", redacted)

    def test_redacts_wrapped_query_values(self):
        redacted = gcloud_remote_login.redact(
            "callback failed:\nstate=test-state&code=test-code"
        )
        self.assertNotIn("test-state", redacted)
        self.assertNotIn("test-code", redacted)


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.bin_dir = pathlib.Path(self.tempdir.name)
        write_executable(self.bin_dir / "firefox-work", "#!/bin/sh\nexit 0\n")

    def environment(self):
        return mock.patch.dict(
            os.environ,
            {"PATH": f"{self.bin_dir}:{os.environ.get('PATH', '')}"},
        )

    def install_success_helpers(self):
        write_executable(
            self.bin_dir / "ssh",
            f"""\
            #!{sys.executable}
            import sys
            print('gcloud auth login --remote-bootstrap="{BOOTSTRAP_URL}"', flush=True)
            callback = sys.stdin.readline().strip()
            if callback != {CALLBACK_URL!r}:
                print("unexpected callback", file=sys.stderr)
                raise SystemExit(3)
            print("__GCLOUD_REMOTE_LOGIN_SUCCESS__")
            """,
        )
        write_executable(
            self.bin_dir / "gcloud",
            f"""\
            #!{sys.executable}
            import os
            import sys
            confirmation = sys.stdin.readline().strip()
            if confirmation != "y":
                raise SystemExit(4)
            if not os.environ.get("BROWSER", "").endswith("firefox-work"):
                raise SystemExit(5)
            print({CALLBACK_URL!r}, flush=True)
            """,
        )

    def test_end_to_end_forwards_callback(self):
        self.install_success_helpers()
        stdout = io.StringIO()
        with self.environment(), contextlib.redirect_stdout(stdout):
            status = gcloud_remote_login.main(["--timeout", "5"])
        self.assertEqual(status, 0)
        self.assertIn("updated successfully", stdout.getvalue())
        self.assertNotIn("test-code", stdout.getvalue())

    def test_cached_credentials_skip_local_gcloud(self):
        write_executable(
            self.bin_dir / "ssh",
            f"""\
            #!{sys.executable}
            print("__GCLOUD_REMOTE_LOGIN_SUCCESS__")
            """,
        )
        write_executable(
            self.bin_dir / "gcloud",
            "#!/bin/sh\necho should-not-run >&2\nexit 99\n",
        )
        stdout = io.StringIO()
        with self.environment(), contextlib.redirect_stdout(stdout):
            status = gcloud_remote_login.main(["--timeout", "5"])
        self.assertEqual(status, 0)
        self.assertIn("valid and synchronized", stdout.getvalue())

    def test_local_helper_failure_is_redacted(self):
        write_executable(
            self.bin_dir / "ssh",
            f"""\
            #!{sys.executable}
            import sys
            print('gcloud auth login --remote-bootstrap="{BOOTSTRAP_URL}"', flush=True)
            sys.stdin.readline()
            """,
        )
        write_executable(
            self.bin_dir / "gcloud",
            f"""\
            #!{sys.executable}
            import sys
            sys.stdin.readline()
            print("failed at {CALLBACK_URL}")
            raise SystemExit(7)
            """,
        )
        stderr = io.StringIO()
        with self.environment(), contextlib.redirect_stderr(stderr):
            status = gcloud_remote_login.main(["--timeout", "5"])
        self.assertEqual(status, 1)
        self.assertIn("local gcloud browser helper failed", stderr.getvalue())
        self.assertNotIn("test-code", stderr.getvalue())

    def test_timeout_terminates_child(self):
        write_executable(
            self.bin_dir / "ssh",
            f"""\
            #!{sys.executable}
            import time
            time.sleep(10)
            """,
        )
        write_executable(self.bin_dir / "gcloud", "#!/bin/sh\nexit 0\n")
        started = time.monotonic()
        stderr = io.StringIO()
        with self.environment(), contextlib.redirect_stderr(stderr):
            status = gcloud_remote_login.main(["--timeout", "0.1"])
        self.assertEqual(status, 1)
        self.assertLess(time.monotonic() - started, 4)
        self.assertIn("timed out", stderr.getvalue())


class RemoteScriptTests(unittest.TestCase):
    def test_fallback_gcloud_and_quota_project_preservation(self):
        with tempfile.TemporaryDirectory() as directory:
            home = pathlib.Path(directory)
            gcloud = home / "google-cloud-sdk/bin/gcloud"
            gcloud.parent.mkdir(parents=True)
            log = home / "gcloud.log"
            adc_dir = home / ".config/gcloud"
            adc_dir.mkdir(parents=True)
            (adc_dir / "application_default_credentials.json").write_text(
                '{"quota_project_id":"existing-project"}', encoding="utf-8"
            )
            write_executable(
                gcloud,
                f"""\
                #!{sys.executable}
                import json
                import pathlib
                import sys
                log = pathlib.Path({str(log)!r})
                with log.open("a", encoding="utf-8") as handle:
                    handle.write(json.dumps(sys.argv[1:]) + "\\n")
                if sys.argv[1] == "version":
                    print('{{"Google Cloud SDK": "564.0.0"}}')
                elif sys.argv[1:4] == ["config", "get-value", "account"]:
                    print("user@example.com")
                raise SystemExit(0)
                """,
            )
            result = subprocess.run(
                [
                    "sh",
                    "-c",
                    gcloud_remote_login.REMOTE_SCRIPT,
                    "gcloud-remote-login",
                    "",
                    "",
                    "",
                    "0",
                ],
                env={"HOME": str(home), "PATH": make_remote_path(home)},
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = log.read_text(encoding="utf-8")
            self.assertIn('"auth", "login", "user@example.com"', calls)
            self.assertIn(
                '"set-quota-project", "existing-project", "--quiet"', calls
            )

    def test_old_remote_gcloud_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            gcloud = pathlib.Path(directory) / "gcloud"
            write_executable(
                gcloud,
                """\
                #!/bin/sh
                echo '{"Google Cloud SDK": "371.0.0"}'
                """,
            )
            result = subprocess.run(
                [
                    "sh",
                    "-c",
                    gcloud_remote_login.REMOTE_SCRIPT,
                    "gcloud-remote-login",
                    str(gcloud),
                    "",
                    "",
                    "0",
                ],
                env={"HOME": directory, "PATH": make_remote_path(pathlib.Path(directory))},
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("too old", result.stderr)


if __name__ == "__main__":
    unittest.main()
