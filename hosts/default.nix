{
  inputs,
  sharedModules,
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
          ../modules/desktop.nix
          ../modules/regreet.nix
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixshark";}
        ]
        ++ sharedModules;
    };
    nixwork = nixosSystem {
      modules =
        [
          ./nixwork
          ../modules/desktop.nix
          ../modules/regreet.nix
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixwork";}
          inputs.hardware.nixosModules.framework-13-7040-amd
        ]
        ++ sharedModules;
    };
  };
}
