{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking.hostName = "nixwork";

  environment.systemPackages = with pkgs; [
    inputs.agenix.packages.x86_64-linux.default
    devenv

    xdg-utils
    deploy-rs
  ];

  services.power-profiles-daemon.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  services.syncthing = {
    enable = true;
    user = "tarttelin";
    dataDir = "/home/tarttelin/sync";
    configDir = "/home/tarttelin/.config/syncthing";
  };

  services.fwupd.enable = true;

  system.stateVersion = "24.05";
}
