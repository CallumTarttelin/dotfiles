{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.go-tools = pkgs.buildEnv {
      name = "go-tools";
      # go installed via HM programs.go (sets GOPATH etc.)
      paths = with pkgs; [air lazygit];
    };
  };

  flake.nixosModules.go-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.go-tools
    ];
  };
}
