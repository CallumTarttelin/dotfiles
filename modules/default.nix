{
  self,
  inputs,
  default,
  lib,
  ...
}: let
  # system-agnostic args
  module_args._module.args = {
    inherit default inputs self;
  };

  # All feature + system nixosModules are auto-registered via flake-parts imports
  # below. These lists collect them for hosts/default.nix to use.
  allModules = [
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
      };
    }

    inputs.agenix.nixosModules.default
    inputs.hm.nixosModules.default
    module_args

    self.nixosModules.core
    self.nixosModules.network

    # Feature modules (all imported, activate via features.*.enable)
    self.nixosModules.bluetooth
    self.nixosModules.yubikey
    self.nixosModules.gaming
    self.nixosModules.virtualization
    self.nixosModules.desktop
    self.nixosModules.greeter
    self.nixosModules.logiops
    self.nixosModules.atuin-server
    self.nixosModules.k3s
  ];
in {
  imports = [
    # Auto-discover all flake-parts modules under features/ and system/
    (import ../lib/import-modules.nix lib ./features)
    (import ../lib/import-modules.nix lib ./system)
    {
      _module.args = {
        inherit module_args allModules;
        # Keep backwards compat for hosts/default.nix during migration
        sharedModules = allModules;
        desktopModules = allModules;
      };
    }
  ];
}
