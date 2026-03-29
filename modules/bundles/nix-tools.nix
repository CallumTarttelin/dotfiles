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

  flake.nixosModules.nix-tools = {config, lib, pkgs, ...}: {
    options.bundles.nix-tools.enable = lib.mkEnableOption "Nix development tools (alejandra, deploy-rs, statix)";
    config = lib.mkIf config.bundles.nix-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.nix-tools
      ];
    };
  };
}
