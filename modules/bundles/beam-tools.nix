{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.gleam = pkgs.gleam.overrideAttrs (old: {
      checkFlags =
        (old.checkFlags or [])
        ++ [
          "--skip=tests::escript_success_with_dependency"
        ];
    });

    packages.beam-tools = pkgs.buildEnv {
      name = "beam-tools";
      paths = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.gleam
        pkgs.erlang
        pkgs.elixir
      ];
    };
  };

  flake.nixosModules.beam-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.bundles.beam-tools.enable = lib.mkEnableOption "BEAM tools (gleam, erlang, elixir)";
    config = lib.mkIf config.bundles.beam-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.beam-tools
      ];
    };
  };
}
