{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.python-tools = pkgs.buildEnv {
      name = "python-tools";
      paths = with pkgs; [python3 uv python313Packages.ptpython];
    };
  };

  flake.nixosModules.python-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.python-tools
    ];
  };
}
