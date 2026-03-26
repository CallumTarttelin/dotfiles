{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.drawing = pkgs.buildEnv {
      name = "drawing";
      paths = with pkgs; [
        easyeffects
      ];
    };
  };

  flake.nixosModules.drawing = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.drawing
    ];
  };
}
