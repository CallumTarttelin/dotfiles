_: {
  flake.nixosModules.bluetooth = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.features.bluetooth.enable = lib.mkEnableOption "Bluetooth support";

    config = lib.mkIf config.features.bluetooth.enable {
      hardware.bluetooth.enable = true;

      environment.systemPackages = with pkgs; [
        bluez
      ];
    };
  };
}
