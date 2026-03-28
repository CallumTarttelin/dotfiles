{self, ...}: {
  perSystem = {pkgs, ...}: let
    mpvConf = pkgs.writeText "mpv.conf" ''
      hwdec=auto-safe
      vo=gpu
      profile=gpu-hq
      gpu-context=wayland
      save-position-on-quit=yes
    '';

    mpvConfigDir = pkgs.runCommand "mpv-config" {} ''
      mkdir -p $out
      cp ${mpvConf} $out/mpv.conf
    '';

    myMpv = pkgs.symlinkJoin {
      name = "myMpv";
      paths = [pkgs.mpv];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/mpv \
          --add-flags "--config-dir=${mpvConfigDir}"
      '';
      meta.mainProgram = "mpv";
    };

    myZathura = pkgs.symlinkJoin {
      name = "myZathura";
      paths = [pkgs.zathura];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/zathura \
          --add-flags "--config-dir=${pkgs.runCommand "zathura-config" {} ''
            mkdir -p $out
            echo "set database sqlite" > $out/zathurarc
          ''}"
      '';
      meta.mainProgram = "zathura";
    };
  in {
    packages.media = pkgs.buildEnv {
      name = "media";
      paths = [
        myMpv
        myZathura
        pkgs.spotify
        pkgs.pulsemixer
        pkgs.qpwgraph
        pkgs.feh
      ];
    };
  };

  flake.nixosModules.media = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.media
    ];
  };
}
