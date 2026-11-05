{
  writeShellApplication,
  python3,
  curl,
  gitMinimal,
  flake,
}:
writeShellApplication {
  name = "update-inference";
  runtimeInputs = [python3 curl gitMinimal];
  text = ''
    if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -f "$repo_root/pkgs/inference-tools/pins.json" ]]; then
      :
    else
      repo_root=${flake}
    fi
    exec python3 ${./update.py} "$repo_root" "$@"
  '';
}
