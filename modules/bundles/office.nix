{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.office = pkgs.buildEnv {
      name = "office";
      paths = with pkgs; [
        libreoffice-fresh
        obsidian
      ];
    };
  };

  flake.nixosModules.office = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.office
    ];
  };
}
