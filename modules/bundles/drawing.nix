{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.drawing = pkgs.buildEnv {
      name = "drawing";
      paths = with pkgs; [
        easyeffects
      ];
    };
  };

  flake.nixosModules.drawing = {config, lib, pkgs, ...}: {
    options.bundles.drawing.enable = lib.mkEnableOption "drawing/audio tools (easyeffects)";
    config = lib.mkIf config.bundles.drawing.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.drawing
      ];
    };
  };
}
