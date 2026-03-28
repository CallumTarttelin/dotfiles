{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.nix-tools = pkgs.buildEnv {
      name = "nix-tools";
      paths = [
        pkgs.alejandra
        pkgs.deadnix
        pkgs.statix
        pkgs.deploy-rs
        self.packages.${pkgs.stdenv.hostPlatform.system}.pre-update
        self.packages.${pkgs.stdenv.hostPlatform.system}.update-t3code
      ];
    };
  };

  flake.nixosModules.nix-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.nix-tools
    ];
  };
}
