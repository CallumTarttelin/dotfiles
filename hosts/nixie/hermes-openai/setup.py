"""Provision the Nix-managed OpenAI profile without cloning private Hermes data."""
import argparse
import json
import os
from pathlib import Path
import tempfile


def write_private(path, content):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        temporary.write(content)
        temporary.flush()
        os.fsync(temporary.fileno())
        temporary_path = Path(temporary.name)
    os.replace(temporary_path, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings", type=Path, required=True)
    parser.add_argument("--credentials", type=Path, required=True)
    parser.add_argument("--policy", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    from hermes_cli.profiles import create_profile, get_profile_dir
    from hermes_cli.config_defaults import DEFAULT_CONFIG

    profile = get_profile_dir("openai")
    marker = profile / ".nixie-managed"
    if profile.exists() and not marker.exists():
        raise RuntimeError(f"Refusing to overwrite an unmanaged profile: {profile}")
    if not profile.exists():
        create_profile("openai", no_alias=True, no_skills=True,
                       description="OpenAI subscription — separate memory; no private sources")
        marker.touch(mode=0o600)
    settings = json.loads(args.settings.read_text())
    settings["_config_version"] = DEFAULT_CONFIG["_config_version"]
    settings["terminal"]["cwd"] = str(profile / "workspace")
    write_private(profile / "config.yaml", json.dumps(settings, indent=2).encode())
    write_private(profile / ".env", args.credentials.read_bytes())
    write_private(profile / "SOUL.md", args.policy.read_bytes())


if __name__ == "__main__":
    main()
