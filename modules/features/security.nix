_: {
  flake.nixosModules.security-tools = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.features.security;
  in {
    options.features.security = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Security tools (password managers, YubiKey, etc.)";
      };
      yubikey = lib.mkEnableOption "YubiKey hardware support";
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        home-manager.users.tarttelin = {
          home.packages = with pkgs; [
            keepassxc
            # bitwarden-desktop pulls insecure electron_39.
            # bitwarden-desktop
            # bitwarden-cli
          ];
        };
      }
      (lib.mkIf cfg.yubikey {
        services.udev = {
          enable = true;
          extraRules = ''
            SUBSYSTEM=="usb", ATTR{idVendor}=="1050", MODE="0660", GROUP="yubikey"
          '';
        };
        services.pcscd.enable = true;

        environment.systemPackages = with pkgs; [
          yubikey-manager
          yubioath-flutter
          yubikey-personalization
          age-plugin-yubikey
        ];
      })
    ]);
  };
}
