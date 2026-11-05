{
  updateJetbrainsToolbox,
  updateT3code,
  updateInference,
  writeShellApplication,
}:
writeShellApplication {
  name = "pre-update";

  runtimeInputs = [
    updateJetbrainsToolbox
    updateT3code
    updateInference
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
        update-inference
        ;;
      t3code)
        update-t3code "$@"
        ;;
      jetbrains-toolbox|toolbox)
        update-jetbrains-toolbox "$@"
        ;;
      inference|hermes|phala|cliproxyapi)
        update-inference "$@"
        ;;
      *)
        update-t3code "$target" "$@"
        ;;
    esac
  '';
}
