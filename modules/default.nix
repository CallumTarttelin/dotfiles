{
  self,
  inputs,
  default,
  lib,
  ...
}: let
  module_args._module.args = {
    inherit default inputs self;
  };

  # All modules loaded on every host — activate via enable options.
  # self.nixosModules is auto-populated by import-modules.nix discovery.
  allModules =
    [
      {
        nixpkgs.overlays = [(import ../overlays {inherit inputs;})];
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
        };
      }
      inputs.agenix.nixosModules.default
      inputs.hm.nixosModules.default
      module_args
    ]
    ++ builtins.attrValues self.nixosModules;
in {
  imports = [
    (import ../lib/import-modules.nix lib ./features)
    (import ../lib/import-modules.nix lib ./system)
    (import ../lib/import-modules.nix lib ./wrapped)
    (import ../lib/import-modules.nix lib ./bundles)
    {
      _module.args = {
        inherit module_args allModules;
      };
    }
  ];
}
