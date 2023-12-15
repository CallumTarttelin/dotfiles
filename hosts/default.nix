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
  };
}
