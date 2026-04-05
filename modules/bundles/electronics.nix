{self, ...}: {
  perSystem = {pkgs, ...}: let
    nrfconnect-wrapped = pkgs.buildFHSEnv {
      name = "nrfconnect";
      targetPkgs = p: [pkgs.nrfconnect pkgs.nrfutil p.segger-jlink-headless p.libusb1 p.udev];
      runScript = "${pkgs.nrfconnect}/bin/nrfconnect";
      extraInstallCommands = ''
        mkdir -p $out/share
        ln -s ${pkgs.nrfconnect}/share/applications $out/share/applications
        ln -s ${pkgs.nrfconnect}/share/icons $out/share/icons
      '';
    };
  in {
    packages.electronics = pkgs.buildEnv {
      name = "electronics";
      paths = with pkgs; [
        kicad
        ngspice
        nrfconnect-wrapped
        # nrfconnect-bluetooth-low-energy
        minicom
        openocd
        nrf-command-line-tools
        segger-jlink-headless
      ];
    };
  };

  flake.nixosModules.electronics = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.bundles.electronics.enable = lib.mkEnableOption "electronics tools (kicad, ngspice)";
    config = lib.mkIf config.bundles.electronics.enable {
      nixpkgs.config.permittedInsecurePackages = [
        "segger-jlink-qt4-874"
      ];
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.electronics
      ];

      services.udev.extraRules = ''
        # SEGGER J-Link
        SUBSYSTEM=="usb", ATTR{idVendor}=="1366", MODE="0666"
        # Nordic Semiconductor nRF DK / Dongle
        SUBSYSTEM=="usb", ATTR{idVendor}=="1915", MODE="0666"
        KERNEL=="ttyACM[0-9]*", SUBSYSTEM=="tty", SUBSYSTEMS=="usb", ATTRS{idVendor}=="1915", MODE="0666", ENV{NRF_CDC_ACM}="1"
      '';
    };
  };
}
