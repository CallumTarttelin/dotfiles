{
  writeShellApplication,
  curl,
  gitMinimal,
  gnused,
  jq,
  nix,
  perl,
  flake,
}:
writeShellApplication {
  name = "update-t3code";

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

    if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -f "$repo_root/pkgs/t3code/default.nix" ]]; then
      :
    elif [[ -f "${flake}/pkgs/t3code/default.nix" ]]; then
      repo_root="${flake}"
    else
      echo "Run update-t3code from the dotfiles repo." >&2
      exit 1
    fi

    package_file="$repo_root/pkgs/t3code/default.nix"
    release_ref="''${1:-latest}"

    case "$release_ref" in
      latest)
        api_url="https://api.github.com/repos/pingdotgg/t3code/releases/latest"
        ;;
      v*)
        api_url="https://api.github.com/repos/pingdotgg/t3code/releases/tags/$release_ref"
        ;;
      *)
        api_url="https://api.github.com/repos/pingdotgg/t3code/releases/tags/v$release_ref"
        ;;
    esac

    release_json="$(
      curl \
        --fail \
        --silent \
        --show-error \
        --location \
        -H 'Accept: application/vnd.github+json' \
        "$api_url"
    )"

    version="$(jq -r '.tag_name | sub("^v"; "")' <<<"$release_json")"
    if [[ -z "$version" || "$version" == "null" ]]; then
      echo "Could not determine the T3 Code version from GitHub." >&2
      exit 1
    fi

    # New releases omit the version from the AppImage filename. Keep support
    # for older tags, and match x86_64 explicitly to avoid the ARM build.
    asset_name="$(jq -r --arg legacy "T3-Code-$version-x86_64.AppImage" '
      [.assets[].name] | map(select(. == "T3-Code-x86_64.AppImage" or . == $legacy))
      | sort_by(. == $legacy) | first // empty
    ' <<<"$release_json")"
    asset_url="$(jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .browser_download_url' <<<"$release_json")"
    if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
      echo "Could not find an x86_64 AppImage release asset for T3 Code $version." >&2
      exit 1
    fi

    hash="$(nix store prefetch-file --json "$asset_url" | jq -r '.hash')"
    if [[ -z "$hash" || "$hash" == "null" ]]; then
      echo "Could not prefetch a hash for $asset_url." >&2
      exit 1
    fi

    current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$package_file")"
    current_hash="$(sed -n 's/^[[:space:]]*hash = "\([^"]*\)";/\1/p' "$package_file")"
    current_asset="$(sed -n 's/^[[:space:]]*assetName = "\([^"]*\)";/\1/p' "$package_file")"

    if [[ "$current_version" == "$version" && "$current_hash" == "$hash" && "$current_asset" == "$asset_name" ]]; then
      echo "t3code is already up to date at $version"
      exit 0
    fi

    VERSION="$version" HASH="$hash" ASSET_NAME="$asset_name" perl -0pi -e '
      s/version = "[^"]+";/version = "$ENV{VERSION}";/;
      s/hash = "[^"]+";/hash = "$ENV{HASH}";/;
      s/assetName = "[^"]+";/assetName = "$ENV{ASSET_NAME}";/;
    ' "$package_file"

    echo "Updated t3code: ''${current_version:-unknown} -> $version"
    echo "New hash: $hash"
  '';
}
