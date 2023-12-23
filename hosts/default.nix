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
          ../modules/games.nix
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixshark";}
          inputs.hardware.nixosModules.common-pc
          inputs.hardware.nixosModules.common-pc-ssd
          inputs.hardware.nixosModules.common-cpu-amd
          inputs.hardware.nixosModules.common-cpu-amd-pstate
          inputs.hardware.nixosModules.common-gpu-amd
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
