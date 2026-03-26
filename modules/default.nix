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
    self.nixosModules.hyprland-desktop
    self.nixosModules.logiops
    self.nixosModules.atuin-server
    self.nixosModules.k3s
    self.nixosModules.shell

    # Wrapped packages (always available, no feature flag)
    self.nixosModules.ghostty
    self.nixosModules.foot
    self.nixosModules.starship
    self.nixosModules.mako
    self.nixosModules.wofi
    self.nixosModules.waybar
    self.nixosModules.myZsh
    self.nixosModules.neovim

    # Bundled packages (always available, no feature flag)
    self.nixosModules.social
    self.nixosModules.editors
    self.nixosModules.office
    self.nixosModules.llms
    self.nixosModules.security
    self.nixosModules.media
    self.nixosModules.drawing
    self.nixosModules.electronics
    self.nixosModules.work
    self.nixosModules.go-tools
    self.nixosModules.jvm-tools
    self.nixosModules.web-tools
    self.nixosModules.python-tools
    self.nixosModules.beam-tools
    self.nixosModules.misc-langs
    self.nixosModules.k8s-tools
    self.nixosModules.build-tools
    self.nixosModules.cloud-tools
    self.nixosModules.rust-tools
  ];
in {
  imports = [
    # Auto-discover all flake-parts modules
    (import ../lib/import-modules.nix lib ./features)
    (import ../lib/import-modules.nix lib ./system)
    (import ../lib/import-modules.nix lib ./wrapped)
    (import ../lib/import-modules.nix lib ./bundles)
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
