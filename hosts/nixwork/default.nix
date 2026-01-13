{
  pkgs,
  inputs,
  lib,
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

    xdg-utils
    deploy-rs

    # connmanFull

    claude-code
    socat
    bubblewrap
    opencode
    mitmproxy
    mitmproxy2swagger
    waydroid-helper
    cmst
    connman-gtk
    android-tools
  ];

  virtualisation.waydroid.enable = true;

  services.power-profiles-daemon.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  services.connman = {
    enable = true;
    wifi.backend = "iwd";
  };

  systemd.network.enable = lib.mkDefault false;
  networking.networkmanager.enable = lib.mkDefault false;

  services.fwupd.enable = true;

  system.stateVersion = "24.05";
}
