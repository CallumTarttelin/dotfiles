{
  inputs,
  sharedModules,
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
        ]
        ++ sharedModules;
    };
    nixwork = nixosSystem {
      modules =
        [
          ./nixwork
          ../modules/desktop.nix
          inputs.hardware.nixosModules.framework-13-7040-amd
        ]
        ++ sharedModules;
    };
  };
}
