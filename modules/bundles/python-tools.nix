{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.python-tools = pkgs.buildEnv {
      name = "python-tools";
      paths = with pkgs; [python3 uv python313Packages.ptpython];
    };
  };

  flake.nixosModules.python-tools = {config, lib, pkgs, ...}: {
    options.bundles.python-tools.enable = lib.mkEnableOption "Python development tools";
    config = lib.mkIf config.bundles.python-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.python-tools
      ];
    };
  };
}
