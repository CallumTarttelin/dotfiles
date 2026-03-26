{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.social = pkgs.buildEnv {
      name = "social";
      paths = with pkgs; [discord slack];
    };
  };

  flake.nixosModules.social = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.social
    ];
  };
}
