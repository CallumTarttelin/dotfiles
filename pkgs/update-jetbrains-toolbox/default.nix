{
  curl,
  flake,
  gitMinimal,
  gnused,
  jq,
  nix,
  perl,
  writeShellApplication,
}:
writeShellApplication {
  name = "update-jetbrains-toolbox";

  runtimeInputs = [
    curl
    gitMinimal
    gnused
    jq
    nix
    perl
  ];

  text = ''
    set -euo pipefail

    if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -f "$repo_root/pkgs/jetbrains-toolbox/default.nix" ]]; then
      :
    elif [[ -f "${flake}/pkgs/jetbrains-toolbox/default.nix" ]]; then
      repo_root="${flake}"
    else
      echo "Run update-jetbrains-toolbox from the dotfiles repo." >&2
      exit 1
    fi

    package_file="$repo_root/pkgs/jetbrains-toolbox/default.nix"
    release_ref="''${1:-latest}"

    if [[ "$release_ref" != "latest" ]]; then
      echo "update-jetbrains-toolbox currently supports only the latest release." >&2
      exit 1
    fi

    release_json="$(
      curl \
        --fail \
        --silent \
        --show-error \
        --location \
        -H 'Accept: application/json' \
        "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
    )"

    version="$(jq -r '.TBA[0].build' <<<"$release_json")"
    x86_url="$(jq -r '.TBA[0].downloads.linux.link' <<<"$release_json")"
    aarch64_url="$(jq -r '.TBA[0].downloads.linuxARM64.link' <<<"$release_json")"

    if [[ -z "$version" || "$version" == "null" ]]; then
      echo "Could not determine the JetBrains Toolbox build from JetBrains releases API." >&2
      exit 1
    fi

    if [[ -z "$x86_url" || "$x86_url" == "null" || -z "$aarch64_url" || "$aarch64_url" == "null" ]]; then
      echo "Could not determine JetBrains Toolbox Linux download URLs." >&2
      exit 1
    fi

    x86_hash="$(nix store prefetch-file --unpack --json "$x86_url" | jq -r '.hash')"
    aarch64_hash="$(nix store prefetch-file --unpack --json "$aarch64_url" | jq -r '.hash')"

    if [[ -z "$x86_hash" || "$x86_hash" == "null" || -z "$aarch64_hash" || "$aarch64_hash" == "null" ]]; then
      echo "Could not prefetch JetBrains Toolbox hashes." >&2
      exit 1
    fi

    current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$package_file")"
    current_x86_hash="$(sed -n 's/^[[:space:]]*x86_64-linux = "\([^"]*\)";/\1/p' "$package_file")"
    current_aarch64_hash="$(sed -n 's/^[[:space:]]*aarch64-linux = "\([^"]*\)";/\1/p' "$package_file")"

    if [[ "$current_version" == "$version" && "$current_x86_hash" == "$x86_hash" && "$current_aarch64_hash" == "$aarch64_hash" ]]; then
      echo "jetbrains-toolbox is already up to date at $version"
      exit 0
    fi

    VERSION="$version" X86_HASH="$x86_hash" AARCH64_HASH="$aarch64_hash" perl -0pi -e '
      s/version = "[^"]+";/version = "$ENV{VERSION}";/;
      s/x86_64-linux = "[^"]+";/x86_64-linux = "$ENV{X86_HASH}";/;
      s/aarch64-linux = "[^"]+";/aarch64-linux = "$ENV{AARCH64_HASH}";/;
    ' "$package_file"

    echo "Updated jetbrains-toolbox: ''${current_version:-unknown} -> $version"
    echo "x86_64-linux hash: $x86_hash"
    echo "aarch64-linux hash: $aarch64_hash"
  '';
}
