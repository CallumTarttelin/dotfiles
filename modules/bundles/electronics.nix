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

  flake.nixosModules.electronics = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.electronics
    ];
  };
}
