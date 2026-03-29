{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.electronics = pkgs.buildEnv {
      name = "electronics";
      paths = with pkgs; [
        kicad
        ngspice
      ];
    };
  };

  flake.nixosModules.electronics = {config, lib, pkgs, ...}: {
    options.bundles.electronics.enable = lib.mkEnableOption "electronics tools (kicad, ngspice)";
    config = lib.mkIf config.bundles.electronics.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.electronics
      ];
    };
  };
}
