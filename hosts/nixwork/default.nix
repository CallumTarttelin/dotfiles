{
  pkgs,
  inputs,
  lib,
  ...
}: let
  frameworkModuleNeedsBackport =
    !(builtins.elem "modules_install" (pkgs.linuxPackages.framework-laptop-kmod.installTargets or []));
in {
  imports = [
    ./hardware-configuration.nix
    ./backup.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  # FIXME: Remove this backport of nixpkgs PR #575818 once nixos-unstable
  # includes it. Check the upstream package on each update and warn below.
  # https://github.com/NixOS/nixpkgs/commit/e81ffa28fd6639477befaa7fd2a925a5943e130c
  boot.kernelPackages = lib.mkIf frameworkModuleNeedsBackport (
    pkgs.linuxPackages.extend (_: kernelPackages: {
      framework-laptop-kmod = kernelPackages.framework-laptop-kmod.overrideAttrs (old: {
        installPhase = null;
        installTargets = ["modules_install"];
        makeFlags =
          (old.makeFlags or [])
          ++ [
            "INSTALL_MOD_PATH=${builtins.placeholder "out"}"
            "INSTALL_MOD_DIR=extra"
            "DEPMOD=true"
          ];
      });
    })
  );

  warnings =
    lib.optional (!frameworkModuleNeedsBackport)
    "FIXME: nixpkgs now installs framework-laptop-kmod through modules_install. Remove the PR #575818 backport and its detection/warning from hosts/nixwork/default.nix.";

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
