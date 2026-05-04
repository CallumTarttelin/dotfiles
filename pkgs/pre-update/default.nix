{
  updateJetbrainsToolbox,
  updateT3code,
  writeShellApplication,
}:
writeShellApplication {
  name = "pre-update";

  runtimeInputs = [
    updateJetbrainsToolbox
    updateT3code
  ];

  text = ''
    set -euo pipefail

    target="''${1:-all}"
    if [[ "$#" -gt 0 ]]; then
      shift
    fi

    case "$target" in
      all)
        update-t3code
        update-jetbrains-toolbox
        ;;
      t3code)
        update-t3code "$@"
        ;;
      jetbrains-toolbox|toolbox)
        update-jetbrains-toolbox "$@"
        ;;
      *)
        update-t3code "$target" "$@"
        ;;
    esac
  '';
}
