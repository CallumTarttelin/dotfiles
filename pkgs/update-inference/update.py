"""Update release pins together; flake.lock is refreshed by the next CI step."""
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def fetch(url, target):
    subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location",
                    "--retry", "3", url, "--output", str(target)], check=True)


def latest_desktop_release(repo, target):
    # This repository also publishes client-library and gateway releases.
    # GitHub's /latest endpoint can select one of those unrelated products.
    page = 1
    while True:
        fetch(f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}", target)
        releases = json.loads(target.read_text())
        if not releases:
            raise ValueError("Could not find a stable private-ai-proxy desktop release")
        for release in releases:
            if (not release.get("draft") and not release.get("prerelease")
                    and re.fullmatch(r"desktop-v\d+\.\d+\.\d+", release["tag_name"])):
                return release
        page += 1


def main(root):
    root = Path(root)
    pin_file = root / "pkgs/inference-tools/pins.json"
    if not pin_file.exists():
        raise SystemExit("Run update-inference from the dotfiles repository")
    pins = json.loads(pin_file.read_text())
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        releases = {}
        for name, repo in (("cliproxyapi", "router-for-me/CLIProxyAPI"),
                           ("private-ai-proxy", "Dstack-TEE/private-ai-gateway"),
                           ("hermes", "NousResearch/hermes-agent")):
            if name == "private-ai-proxy":
                release = latest_desktop_release(repo, temp / "release.json")
            else:
                fetch(f"https://api.github.com/repos/{repo}/releases/latest", temp / "release.json")
                release = json.loads((temp / "release.json").read_text())
            releases[name] = release
            if name == "hermes":
                continue
            version = release["tag_name"].removeprefix("desktop-").removeprefix("v")
            if not re.fullmatch(r"\d+\.\d+\.\d+", version):
                raise ValueError(f"Unexpected {name} release tag")
            asset = (f"CLIProxyAPI_{version}_linux_amd64.tar.gz" if name == "cliproxyapi"
                     else f"private-ai-proxy-cli-{version}-linux-x64.tar.gz")
            url = next(a["browser_download_url"] for a in release["assets"] if a["name"] == asset)
            fetch(url, temp / "asset.tar.gz")
            digest = hashlib.sha256((temp / "asset.tar.gz").read_bytes()).digest()
            pins[name] = {"version": version, "url": url,
                          "hash": "sha256-" + base64.b64encode(digest).decode()}
        tag = releases["hermes"]["tag_name"]
        if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
            raise ValueError("Unexpected Hermes release tag")
        flake_file = root / "flake.nix"
        flake, count = re.subn(r'hermes-agent.url = "github:NousResearch/hermes-agent/[^"\n]+";',
            f'hermes-agent.url = "github:NousResearch/hermes-agent/{tag}";', flake_file.read_text())
        if count != 1:
            raise ValueError("Expected exactly one pinned Hermes flake input")
        # No source changes until every release asset has been downloaded and hashed.
        pin_file.write_text(json.dumps(pins, indent=2) + "\n")
        flake_file.write_text(flake)
        print("Updated inference release pins; run nix flake update hermes-agent to refresh its lock")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: update-inference <dotfiles-repo>")
    main(sys.argv[1])
