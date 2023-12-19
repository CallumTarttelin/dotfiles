{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking.hostName = "shark";

  environment.systemPackages = with pkgs; [
    rocmPackages.clr
    rocmPackages.clr.icd
  ];

  programs.steam.enable = true;

  system.stateVersion = "22.11";
}
