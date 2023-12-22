{pkgs, ...}: {

  environment.systemPackages = [
    gamescope
    gamemode
    mangohud
    steam-run
  ];

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
}
