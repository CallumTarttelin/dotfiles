{self, ...}: {
  perSystem = {pkgs, ...}: let
    footConf = (pkgs.formats.ini {}).generate "foot.ini" {
      main = {
        font = "JetBrainsMono Nerd Font Mono:size=12";
      };
      colors = {
        alpha = 0.6;
        foreground = "FCFCFA";
        background = "000000";
        regular0 = "403E41";
        regular1 = "FF6188";
        regular2 = "A9DC76";
        regular3 = "FFD866";
        regular4 = "FC9867";
        regular5 = "AB9DF2";
        regular6 = "78DCE8";
        regular7 = "FCFCFA";
      };
    };
  in {
    packages.myFoot = pkgs.symlinkJoin {
      name = "myFoot";
      paths = [pkgs.foot];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/foot \
          --add-flags "--config=${footConf}"
      '';
    };
  };

  flake.nixosModules.foot = {config, lib, pkgs, ...}: {
    options.wrapped.foot.enable = lib.mkEnableOption "foot terminal";
    config = lib.mkIf config.wrapped.foot.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.myFoot
      ];
    };
  };
}
