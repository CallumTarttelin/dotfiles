{pkgs, inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking.hostName = "nixshark";

  environment.systemPackages = with pkgs; [
    rocmPackages.clr
    rocmPackages.clr.icd

    inputs.agenix.packages.x86_64-linux.default
    inputs.devenv.packages.x86_64-linux.devenv
  ];

  services.syncthing = {
    enable = true;
    user = "tarttelin";
    dataDir = "/home/tarttelin/sync";
    configDir = "/home/tarttelin/.config/syncthing";
  };

  programs.steam.enable = true;

  system.stateVersion = "22.11";
}
