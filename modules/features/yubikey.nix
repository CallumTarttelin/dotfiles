_: {
  flake.nixosModules.yubikey = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.features.yubikey.enable = lib.mkEnableOption "YubiKey support";

    config = lib.mkIf config.features.yubikey.enable {
      services.udev = {
        enable = true;
        extraRules = ''
          SUBSYSTEM=="usb", ATTR{idVendor}=="1050", MODE="0660", GROUP="yubikey"
        '';
      };

      environment.systemPackages = with pkgs; [
        yubikey-manager
        yubioath-flutter
        yubikey-personalization
        age-plugin-yubikey
      ];

      services.pcscd.enable = true;
    };
  };
}
