_: {
  flake.nixosModules.gaming = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.features.gaming.enable = lib.mkEnableOption "Gaming (Steam, Gamescope, etc.)";

    config = lib.mkIf config.features.gaming.enable {
      environment.systemPackages = with pkgs; [
        gamescope
        gamemode
        mangohud
        steam-run
        protonup-ng
        protonup-qt
        protontricks
        oversteer
        linuxConsoleTools
        ckan
      ];

      nixpkgs.config.packageOverrides = pkgs: {
        steam = pkgs.steam.override {
          extraPkgs = pkgs:
            with pkgs; [
              libxcursor
              libxi
              libxinerama
              libxscrnsaver
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
    };
  };
}
