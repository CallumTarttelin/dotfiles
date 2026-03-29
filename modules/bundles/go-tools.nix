{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.go-tools = pkgs.buildEnv {
      name = "go-tools";
      paths = with pkgs; [go air gotools golangci-lint delve];
    };

    devShells.go = pkgs.mkShell {
      packages = with pkgs; [go air gotools golangci-lint delve];
    };
  };

  flake.nixosModules.go-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.bundles.go-tools.enable = lib.mkEnableOption "Go development tools";
    config = lib.mkIf config.bundles.go-tools.enable {
      home-manager.users.tarttelin = {
        home.packages = [
          self.packages.${pkgs.stdenv.hostPlatform.system}.go-tools
        ];
        programs.go.enable = true;
      };
    };
  };
}
