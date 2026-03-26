{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.go-tools = pkgs.buildEnv {
      name = "go-tools";
      paths = with pkgs; [go air lazygit];
    };

    devShells.go = pkgs.mkShell {
      packages = with pkgs; [go air lazygit];
    };
  };

  flake.nixosModules.go-tools = {pkgs, ...}: {
    home-manager.users.tarttelin = {
      home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.go-tools
      ];
      programs.go.enable = true;
    };
  };
}
