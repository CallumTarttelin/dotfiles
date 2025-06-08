{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    gamescope
    gamemode
    mangohud
    steam-run
    protonup
    protonup-qt
    protontricks
    oversteer
    linuxConsoleTools
  ];

  nixpkgs.config.packageOverrides = pkgs: {
    steam = pkgs.steam.override {
      extraPkgs = pkgs:
        with pkgs; [
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
          qpdf
        ];
    };
  };

  programs.steam.enable = true;
  programs.steam.gamescopeSession.enable = true;
  programs.gamemode.enable = true;
  programs.gamescope.enable = true;
}
