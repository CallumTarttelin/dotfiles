{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.beam-tools = pkgs.buildEnv {
      name = "beam-tools";
      paths = with pkgs; [gleam erlang elixir];
    };
  };

  flake.nixosModules.beam-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.beam-tools
    ];
  };
}
