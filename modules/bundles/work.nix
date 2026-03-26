{self, inputs, ...}: {
  perSystem = {pkgs, ...}: let
    oldUnfree = import inputs.oldpkgs {
      config.allowUnfree = true;
      system = pkgs.stdenv.hostPlatform.system;
    };
  in {
    packages.work = pkgs.buildEnv {
      name = "work";
      paths = [
        oldUnfree.citrix_workspace_23_09_0
      ];
    };
  };

  flake.nixosModules.work = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.work
    ];
  };
}
