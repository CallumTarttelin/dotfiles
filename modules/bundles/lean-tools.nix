{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.lean-tools = pkgs.buildEnv {
      name = "lean-tools";
      paths = [pkgs.elan];
    };

    devShells.lean = pkgs.mkShell {
      packages = [pkgs.elan];
    };
  };

  flake.nixosModules.lean-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.bundles.lean-tools.enable = lib.mkEnableOption "Lean development tools (elan, Lean, Lake)";
    config = lib.mkIf config.bundles.lean-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.lean-tools
      ];
    };
  };
}
