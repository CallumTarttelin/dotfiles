{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.office = pkgs.buildEnv {
      name = "office";
      paths = with pkgs; [
        libreoffice-fresh
        obsidian
      ];
    };
  };

  flake.nixosModules.office = {config, lib, pkgs, ...}: {
    options.bundles.office.enable = lib.mkEnableOption "office apps (LibreOffice, Obsidian)";
    config = lib.mkIf config.bundles.office.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.office
      ];
    };
  };
}
