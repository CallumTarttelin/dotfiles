{
  updateT3code,
  writeShellApplication,
}:
writeShellApplication {
  name = "pre-update";

  runtimeInputs = [updateT3code];

  text = ''
    set -euo pipefail

    update-t3code "$@"
  '';
}
