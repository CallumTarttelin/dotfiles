{
  inputs,
  desktopModules,
  homeImports,
  ...
}: {
  flake.nixosConfigurations = let
    inherit (inputs.nixpkgs.lib) nixosSystem;
  in {
    nixshark = nixosSystem {
      modules =
        [
          ./nixshark
          ../modules/yubikey.nix
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixshark";}
        ]
        ++ desktopModules;
    };
    nixwork = nixosSystem {
      modules =
        [
          ./nixwork
          ../modules/yubikey.nix
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixwork";}
          inputs.hardware.nixosModules.framework-13-7040-amd
        ]
        ++ desktopModules;
    };
  };
}
