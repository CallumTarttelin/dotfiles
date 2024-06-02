{pkgs, inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
    ./backup.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking.hostName = "nixshark";

  # This adds the Fenix overlay to the flake's package scope
  nixpkgs.overlays = [ inputs.fenix.overlays.default ];

  environment.systemPackages = with pkgs; [
    rocmPackages.clr
    rocmPackages.clr.icd
    powertop

    inputs.agenix.packages.x86_64-linux.default
    devenv

    openssl
    cargo-generate
    cargo-outdated
    aoc-cli
    gcc
    gnumake

    xdg-utils

    via
    vial

    # Use the 'withComponents' package generator to define a Rust toolchain
    (inputs.fenix.packages.x86_64-linux.complete.withComponents [
      "cargo"
      "clippy"
      "rust-src"
      "rustc"
      "rustfmt"
    ])

  ];

  services.xserver.videoDrivers = ["amdgpu"];

  services.flatpak.enable = true;

  powerManagement = {
    enable = true;
    powertop.enable = true;
  };

  services.syncthing = {
    enable = true;
    user = "tarttelin";
    dataDir = "/home/tarttelin/sync";
    configDir = "/home/tarttelin/.config/syncthing";
  };

  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0660", GROUP="100", TAG+="uaccess", TAG+="udev-acl"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="100", TAG+="uaccess", TAG+="udev-acl"
  '';

  system.stateVersion = "22.11";
}
