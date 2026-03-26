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

  flake.nixosModules.rust-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.rust-tools
    ];
  };
}
