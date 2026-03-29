{self, ...}: {
  perSystem = {pkgs, ...}: let
    makoConf = pkgs.writeText "mako-config" ''
      default-timeout=3000
      ignore-timeout=1
    '';
  in {
    packages.myMako = pkgs.symlinkJoin {
      name = "myMako";
      paths = [pkgs.mako];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/mako \
          --add-flags "--config=${makoConf}"
      '';
      meta.mainProgram = "mako";
    };
  };

  flake.nixosModules.mako = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.wrapped.mako.enable = lib.mkEnableOption "mako notifications";
    config = lib.mkIf config.wrapped.mako.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.myMako
      ];
    };
  };
}
