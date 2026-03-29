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
    xdg-utils
    socat
    bubblewrap
    mitmproxy
    mitmproxy2swagger
    waydroid-helper
    android-tools
  ];

  virtualisation.waydroid.enable = true;

  services.syncthing = {
    enable = true;
    user = "tarttelin";
    dataDir = "/home/tarttelin/sync";
    configDir = "/home/tarttelin/.config/syncthing";
  };

  services.power-profiles-daemon.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  services.upower.enable = true;

  services.fwupd.enable = true;

  system.stateVersion = "24.05";
}
