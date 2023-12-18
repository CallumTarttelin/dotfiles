{
  config,
  lib,
  pkgs,
  agenix,
  devenv,
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

  system.stateVersion = "23.11";
}
