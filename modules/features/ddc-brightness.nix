_: {
  flake.nixosModules.ddc-brightness = {
    config,
    lib,
    pkgs,
    ...
  }: let
    ddcBrightness = pkgs.writeShellScriptBin "ddc-brightness" ''
      set -euo pipefail

      usage() {
        echo "usage: ddc-brightness <0-100>" >&2
        exit 2
      }

      [[ $# -eq 1 ]] || usage
      [[ "$1" =~ ^[0-9]+$ ]] || usage

      brightness="$1"
      if (( brightness < 0 || brightness > 100 )); then
        usage
      fi

      for bus in 5 7 8; do
        ${lib.getExe pkgs.ddcutil} setvcp 10 "$brightness" --bus "$bus"
      done
    '';

    ddcBrightnessStep = pkgs.writeShellScriptBin "ddc-brightness-step" ''
      set -euo pipefail

      usage() {
        echo "usage: ddc-brightness-step <delta>" >&2
        echo "example: ddc-brightness-step +10" >&2
        exit 2
      }

      [[ $# -eq 1 ]] || usage
      [[ "$1" =~ ^[+-]?[0-9]+$ ]] || usage

      delta="$1"

      for bus in 5 7 8; do
        current="$(${lib.getExe pkgs.ddcutil} getvcp 10 --bus "$bus" \
          | ${pkgs.gnused}/bin/sed -n 's/.*current value = *\\([0-9][0-9]*\\).*/\\1/p')"

        if [[ -z "$current" ]]; then
          echo "Unable to read brightness for i2c bus $bus" >&2
          exit 1
        fi

        next=$(( current + delta ))
        if (( next < 0 )); then
          next=0
        elif (( next > 100 )); then
          next=100
        fi

        ${lib.getExe pkgs.ddcutil} setvcp 10 "$next" --bus "$bus"
      done
    '';
  in {
    options.features.ddc-brightness.enable = lib.mkEnableOption "DDC/CI brightness control for nixshark monitors";

    config = lib.mkIf config.features.ddc-brightness.enable {
      boot.kernelModules = ["i2c-dev"];

      environment.systemPackages = [
        pkgs.ddcutil
        ddcBrightness
        ddcBrightnessStep
      ];

      services.udev.extraRules = ''
        SUBSYSTEM=="i2c-dev", KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
      '';

      users.groups.i2c = {};
      users.users.tarttelin.extraGroups = ["i2c"];
    };
  };
}
