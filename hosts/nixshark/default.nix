{ config, lib, pkgs, agenix, devenv, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];


  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  system.stateVersion = "22.11";
}
