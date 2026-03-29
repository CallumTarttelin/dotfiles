{inputs, self, ...}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    packages.rust-tools = pkgs.buildEnv {
      name = "rust-tools";
      paths = [
        (inputs.fenix.packages.${system}.complete.withComponents [
          "cargo"
          "clippy"
          "rust-src"
          "rustc"
          "rustfmt"
        ])
        pkgs.cargo-generate
      ];
    };
  };

  flake.nixosModules.rust-tools = {config, lib, pkgs, ...}: {
    options.bundles.rust-tools.enable = lib.mkEnableOption "Rust development tools";
    config = lib.mkIf config.bundles.rust-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.rust-tools
      ];
    };
  };
}
