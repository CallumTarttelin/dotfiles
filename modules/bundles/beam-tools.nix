{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.beam-tools = pkgs.buildEnv {
      name = "beam-tools";
      paths = with pkgs; [gleam erlang elixir];
    };
  };

  flake.nixosModules.beam-tools = {config, lib, pkgs, ...}: {
    options.bundles.beam-tools.enable = lib.mkEnableOption "BEAM tools (gleam, erlang, elixir)";
    config = lib.mkIf config.bundles.beam-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.beam-tools
      ];
    };
  };
}
