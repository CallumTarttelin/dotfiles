{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.media = pkgs.buildEnv {
      name = "media";
      paths = with pkgs; [
        spotify
        pulsemixer
        qpwgraph
        feh
      ];
    };
  };

  flake.nixosModules.media = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.media
    ];
  };
}
