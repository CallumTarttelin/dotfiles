{pkgs, inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking.hostName = "nixwork";

  environment.systemPackages = with pkgs; [
    rocmPackages.clr
    rocmPackages.clr.icd

    inputs.agenix.packages.x86_64-linux.default
    inputs.devenv.packages.x86_64-linux.devenv
  ];

  services.power-profiles-daemon.enable = true;

  services.fwupd.enable = true;

  system.stateVersion = "23.11";
}
