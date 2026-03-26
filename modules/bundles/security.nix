{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.security = pkgs.buildEnv {
      name = "security";
      paths = with pkgs; [keepassxc];
    };
  };

  flake.nixosModules.security = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.security
    ];
  };
}
