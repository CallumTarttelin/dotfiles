#!/usr/bin/env python3
"""Complete gcloud's remote no-browser flow from a local workstation."""

from __future__ import annotations

import argparse
import ipaddress
import os
import re
import selectors
import shlex
import shutil
import signal
import subprocess
import sys
import time
from collections.abc import Sequence
from urllib.parse import parse_qs, urlparse


DEFAULT_HOST = "devbox"
DEFAULT_BROWSER = "firefox-work"
DEFAULT_TIMEOUT = 900.0
OUTPUT_LIMIT = 64 * 1024

BOOTSTRAP_RE = re.compile(
    r"gcloud\s+auth\s+login\s+--remote-bootstrap="
    r'(?:"(?P<double>[^"]+)"|\'(?P<single>[^\']+)\'|(?P<plain>\S+))',
    re.MULTILINE,
)
URL_RE = re.compile(r"https?://[^\s\"'<>]+")
CALLBACK_RE = re.compile(
    r"https://(?:localhost|127(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\])(?::\d+)?/[^\s\"'<>]*"
)


REMOTE_SCRIPT = r"""
set -u

requested_gcloud=$1
requested_account=$2
requested_quota_project=$3
force_login=$4

if [ -n "$requested_gcloud" ]; then
  gcloud_bin=$requested_gcloud
elif command -v gcloud >/dev/null 2>&1; then
  gcloud_bin=$(command -v gcloud)
elif [ -x "$HOME/google-cloud-sdk/bin/gcloud" ]; then
  gcloud_bin=$HOME/google-cloud-sdk/bin/gcloud
else
  echo "gcloud-remote-login: remote gcloud was not found in PATH or at $HOME/google-cloud-sdk/bin/gcloud" >&2
  exit 127
fi

if [ ! -x "$gcloud_bin" ]; then
  echo "gcloud-remote-login: remote gcloud is not executable: $gcloud_bin" >&2
  exit 127
fi

sdk_version=$("$gcloud_bin" version --format=json 2>/dev/null | sed -n 's/.*"Google Cloud SDK"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
sdk_major=${sdk_version%%.*}
case "$sdk_major" in
  ''|*[!0-9]*)
    echo "gcloud-remote-login: could not determine the remote Google Cloud SDK version" >&2
    exit 2
    ;;
esac
if [ "$sdk_major" -lt 372 ]; then
  echo "gcloud-remote-login: remote Google Cloud SDK $sdk_version is too old; version 372.0.0 or newer is required" >&2
  exit 2
fi

account=$requested_account
if [ -z "$account" ]; then
  account=$("$gcloud_bin" config get-value account 2>/dev/null || true)
  if [ "$account" = "(unset)" ]; then
    account=
  fi
fi

quota_project=$requested_quota_project
if [ -z "$quota_project" ]; then
  adc_file=${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}/application_default_credentials.json
  if [ -r "$adc_file" ]; then
    if command -v jq >/dev/null 2>&1; then
      quota_project=$(jq -r '.quota_project_id // empty' "$adc_file" 2>/dev/null || true)
    else
      quota_project=$(sed -n 's/.*"quota_project_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$adc_file" | head -n 1)
    fi
  fi
fi
if [ -z "$quota_project" ]; then
  quota_project=$("$gcloud_bin" config get-value billing/quota_project 2>/dev/null || true)
  if [ "$quota_project" = "(unset)" ]; then
    quota_project=
  fi
fi
if [ -z "$quota_project" ]; then
  quota_project=$("$gcloud_bin" config get-value project 2>/dev/null || true)
  if [ "$quota_project" = "(unset)" ]; then
    quota_project=
  fi
fi

if [ -n "$account" ]; then
  if [ "$force_login" = "1" ]; then
    "$gcloud_bin" auth login "$account" --no-browser --update-adc --force --quiet
  else
    "$gcloud_bin" auth login "$account" --no-browser --update-adc --quiet
  fi
else
  if [ "$force_login" = "1" ]; then
    "$gcloud_bin" auth login --no-browser --update-adc --force --quiet
  else
    "$gcloud_bin" auth login --no-browser --update-adc --quiet
  fi
fi
login_status=$?
if [ "$login_status" -ne 0 ]; then
  exit "$login_status"
fi

quota_status=0
if [ -n "$quota_project" ]; then
  "$gcloud_bin" auth application-default set-quota-project "$quota_project" --quiet || quota_status=$?
fi

if [ "$quota_status" -ne 0 ]; then
  echo "gcloud-remote-login: authentication succeeded, but the ADC quota project could not be restored" >&2
fi
echo "__GCLOUD_REMOTE_LOGIN_SUCCESS__"
""".strip()


class LoginError(RuntimeError):
    """An expected authentication orchestration failure."""


def positive_timeout(value: str) -> float:
    timeout = float(value)
    if timeout <= 0:
        raise argparse.ArgumentTypeError("timeout must be greater than zero")
    return timeout


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="gcloud-remote-login",
        description="Authenticate gcloud and ADC on a remote machine using a local browser.",
    )
    parser.add_argument("host", nargs="?", default=DEFAULT_HOST)
    parser.add_argument("--force", action="store_true", help="force a fresh browser login")
    parser.add_argument("--browser", default=DEFAULT_BROWSER, metavar="EXECUTABLE")
    parser.add_argument("--account", default="", metavar="EMAIL")
    parser.add_argument("--quota-project", default="", metavar="PROJECT")
    parser.add_argument("--remote-gcloud", default="", metavar="PATH")
    parser.add_argument(
        "--timeout",
        default=DEFAULT_TIMEOUT,
        type=positive_timeout,
        metavar="SECONDS",
    )
    return parser.parse_args(argv)


def build_remote_command(args: argparse.Namespace) -> str:
    return shlex.join(
        [
            "sh",
            "-c",
            REMOTE_SCRIPT,
            "gcloud-remote-login",
            args.remote_gcloud,
            args.account,
            args.quota_project,
            "1" if args.force else "0",
        ]
    )


def validate_bootstrap_url(url: str) -> str:
    parsed = urlparse(url)
    query = parse_qs(parsed.query)
    if parsed.scheme != "https" or parsed.hostname != "accounts.google.com":
        raise LoginError("remote gcloud returned an untrusted OAuth bootstrap URL")
    if not parsed.path.startswith("/o/oauth2/"):
        raise LoginError("remote gcloud returned an unexpected OAuth bootstrap path")
    if query.get("token_usage") != ["remote"]:
        raise LoginError("remote gcloud returned a bootstrap URL without remote token usage")
    if not query.get("state", [""])[0]:
        raise LoginError("remote gcloud returned a bootstrap URL without OAuth state")
    return url


def extract_bootstrap(text: str) -> str | None:
    match = BOOTSTRAP_RE.search(text)
    if not match:
        return None
    value = next(group for group in match.groups() if group is not None)
    return validate_bootstrap_url(re.sub(r"\s+", "", value))


def _is_loopback(hostname: str | None) -> bool:
    if hostname == "localhost":
        return True
    if not hostname:
        return False
    try:
        return ipaddress.ip_address(hostname).is_loopback
    except ValueError:
        return False


def validate_callback_url(url: str, expected_state: str) -> str:
    parsed = urlparse(url)
    query = parse_qs(parsed.query)
    if parsed.scheme != "https" or not _is_loopback(parsed.hostname):
        raise LoginError("local gcloud returned a non-loopback OAuth callback")
    if not query.get("code", [""])[0]:
        raise LoginError("local gcloud returned an OAuth callback without an authorization code")
    if query.get("state", [""])[0] != expected_state:
        raise LoginError("local gcloud returned an OAuth callback with mismatched state")
    return url


def extract_callback(text: str, expected_state: str) -> str | None:
    for match in CALLBACK_RE.finditer(text):
        candidate = match.group(0)
        try:
            return validate_callback_url(candidate, expected_state)
        except LoginError:
            continue
    return None


def redact(text: str) -> str:
    text = re.sub(
        r"--remote-bootstrap=(?:\"[^\"]*\"|'[^']*'|\S+)",
        "--remote-bootstrap=<redacted>",
        text,
    )
    text = URL_RE.sub("<redacted-url>", text)
    return re.sub(
        r"(?i)(code|state|code_challenge|client_id)=([^&\s]+)",
        r"\1=<redacted>",
        text,
    )


def append_limited(current: str, chunk: str) -> str:
    combined = current + chunk
    return combined[-OUTPUT_LIMIT:]


def read_until(
    process: subprocess.Popen[bytes],
    extractor,
    deadline: float,
) -> tuple[str | None, str]:
    if process.stdout is None:
        raise LoginError("internal error: child output was not captured")
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    output = ""
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise LoginError("timed out waiting for the authentication flow")
            events = selector.select(min(remaining, 0.25))
            for key, _ in events:
                chunk = os.read(key.fd, 8192)
                if chunk:
                    output = append_limited(output, chunk.decode("utf-8", "replace"))
                    result = extractor(output)
                    if result is not None:
                        return result, output
                else:
                    selector.unregister(key.fileobj)
            if process.poll() is not None and not selector.get_map():
                return None, output
    finally:
        selector.close()


def drain_process(
    process: subprocess.Popen[bytes],
    initial_output: str,
    deadline: float,
) -> tuple[int, str]:
    _, remaining_output = read_until(process, lambda _text: None, deadline)
    return process.wait(), append_limited(initial_output, remaining_output)


def terminate_process(process: subprocess.Popen[bytes] | None) -> None:
    if process is None:
        return
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    for stream in (process.stdin, process.stdout, process.stderr):
        if stream is not None and not stream.closed:
            stream.close()


def format_failure(message: str, output: str) -> LoginError:
    safe_output = redact(output).strip()
    if safe_output:
        safe_output = "\n".join(safe_output.splitlines()[-20:])
        return LoginError(f"{message}:\n{safe_output}")
    return LoginError(message)


def run(args: argparse.Namespace) -> None:
    ssh = shutil.which("ssh")
    gcloud = shutil.which("gcloud")
    browser = shutil.which(args.browser) if os.sep not in args.browser else args.browser
    if not ssh:
        raise LoginError("local ssh executable was not found")
    if not gcloud:
        raise LoginError("local gcloud executable was not found")
    if not browser or not os.path.isfile(browser) or not os.access(browser, os.X_OK):
        raise LoginError(f"browser executable was not found or is not executable: {args.browser}")

    deadline = time.monotonic() + args.timeout
    remote: subprocess.Popen[bytes] | None = None
    helper: subprocess.Popen[bytes] | None = None
    remote_output = ""
    helper_output = ""

    def interrupted(_signum, _frame):
        raise KeyboardInterrupt

    previous_term_handler = signal.signal(signal.SIGTERM, interrupted)
    try:
        print(f"Connecting to {args.host}…", flush=True)
        remote = subprocess.Popen(
            [
                ssh,
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=10",
                args.host,
                build_remote_command(args),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )

        bootstrap, remote_output = read_until(remote, extract_bootstrap, deadline)
        if bootstrap is None:
            remote_status = remote.wait()
            if remote_status != 0:
                raise format_failure("remote gcloud login failed", remote_output)
            if "__GCLOUD_REMOTE_LOGIN_SUCCESS__" not in remote_output:
                raise format_failure("remote login ended without a success marker", remote_output)
            print("Remote gcloud and ADC credentials are valid and synchronized.")
            return

        expected_state = parse_qs(urlparse(bootstrap).query)["state"][0]
        helper_env = os.environ.copy()
        helper_env["BROWSER"] = os.path.abspath(browser)
        helper = subprocess.Popen(
            [gcloud, "auth", "login", f"--remote-bootstrap={bootstrap}"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=helper_env,
            bufsize=0,
        )
        if helper.stdin is None:
            raise LoginError("internal error: local gcloud input was not captured")
        helper.stdin.write(b"y\n")
        helper.stdin.flush()
        helper.stdin.close()
        browser_name = os.path.basename(browser)
        print(
            f"Finish Google sign-in in {browser_name}; this command will continue automatically.",
            flush=True,
        )

        callback, helper_output = read_until(
            helper,
            lambda text: extract_callback(text, expected_state),
            deadline,
        )
        if callback is None:
            helper_status = helper.wait()
            if helper_status != 0:
                raise format_failure("local gcloud browser helper failed", helper_output)
            raise format_failure("local gcloud ended without an OAuth callback", helper_output)

        if remote.stdin is None:
            raise LoginError("internal error: remote gcloud input was not captured")
        remote.stdin.write((callback + "\n").encode())
        remote.stdin.flush()
        remote.stdin.close()

        helper_status, helper_output = drain_process(helper, helper_output, deadline)
        if helper_status != 0:
            raise format_failure("local gcloud browser helper failed", helper_output)

        remote_status, remote_output = drain_process(remote, remote_output, deadline)
        if remote_status != 0:
            raise format_failure("remote gcloud login failed", remote_output)
        if "__GCLOUD_REMOTE_LOGIN_SUCCESS__" not in remote_output:
            raise format_failure("remote login ended without a success marker", remote_output)

        if "authentication succeeded, but the ADC quota project could not be restored" in remote_output:
            print("Authentication succeeded, but the remote ADC quota project could not be restored.", file=sys.stderr)
        print("Remote gcloud and ADC credentials were updated successfully.")
    finally:
        signal.signal(signal.SIGTERM, previous_term_handler)
        terminate_process(helper)
        terminate_process(remote)


def main(argv: Sequence[str] | None = None) -> int:
    try:
        run(parse_args(argv))
        return 0
    except KeyboardInterrupt:
        print("gcloud-remote-login: interrupted", file=sys.stderr)
        return 130
    except LoginError as error:
        print(f"gcloud-remote-login: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
