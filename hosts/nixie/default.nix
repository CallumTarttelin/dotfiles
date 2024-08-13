{pkgs, inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking.hostName = "nixie";

  environment.systemPackages = with pkgs; [
    inputs.agenix.packages.x86_64-linux.default
    devenv

    powertop
    xdg-utils
  ];

  services.syncthing = {
    enable = true;
    user = "tarttelin";
    dataDir = "/home/tarttelin/sync";
    configDir = "/home/tarttelin/.config/syncthing";
    guiAddress = "0.0.0.0:8384";
  };

  services.forgejo = {
    enable = true;
    database.type = "postgres";
    lfs.enable = true;
  };

  services.fwupd.enable = true;

  system.stateVersion = "24.05";
}
