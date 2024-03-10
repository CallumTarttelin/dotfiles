{
  self,
  inputs,
  default,
  ...
}: let
  # system-agnostic args
  module_args._module.args = {
    inherit default inputs self;
  };

  sharedModules = [
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
      };
    }

    inputs.agenix.nixosModules.default
    inputs.hm.nixosModule
    module_args

    self.nixosModules.core
    self.nixosModules.network
  ];
  desktopModules =
    [
      self.nixosModules.desktop
      self.nixosModules.logiops
      self.nixosModules.atuin
      self.nixosModules.greeter
    ]
    ++ sharedModules;
in {
  imports = [
    {
      _module.args = {
        # we need to pass this to HM
        inherit module_args sharedModules desktopModules;
      };
    }
  ];

  flake.nixosModules = {
    core = import ./core.nix;
    network = import ./network.nix;
    desktop = import ./desktop.nix;
    logiops = import ./logiops;
    atuin = import ./atuin.nix;
    greeter = import ./tuigreet.nix;
  };
}
