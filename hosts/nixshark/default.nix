{pkgs, inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
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

    inputs.agenix.packages.x86_64-linux.default
    inputs.devenv.packages.x86_64-linux.devenv

    openssl
    cargo-generate
    cargo-outdated
    aoc-cli
    gcc

    gamescope
    gamemode
    mangohud
    steam-run

    # Use the 'withComponents' package generator to define a Rust toolchain
    (inputs.fenix.packages.x86_64-linux.complete.withComponents [
      "cargo"
      "clippy"
      "rust-src"
      "rustc"
      "rustfmt"
    ])
  ];

  services.syncthing = {
    enable = true;
    user = "tarttelin";
    dataDir = "/home/tarttelin/sync";
    configDir = "/home/tarttelin/.config/syncthing";
  };

  nixpkgs.config.packageOverrides = pkgs: {
    steam = pkgs.steam.override {
      extraPkgs = pkgs: with pkgs; [
        xorg.libXcursor
        xorg.libXi
        xorg.libXinerama
        xorg.libXScrnSaver
        libpng
        libpulseaudio
        libvorbis
        stdenv.cc.cc.lib
        libkrb5
        keyutils

        SDL2
        mono
      ];
    };
  };

  programs.steam.enable = true;

  system.stateVersion = "22.11";
}
