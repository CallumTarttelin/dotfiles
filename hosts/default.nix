{
  inputs,
  desktopModules,
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
          ../modules/yubikey.nix
          ../modules/games.nix
          ../modules/bluetooth.nix
          ../modules/virtualization.nix
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
          ../modules/bluetooth.nix
          ../modules/virtualization.nix
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixwork";}
          inputs.hardware.nixosModules.framework-13-7040-amd
        ]
        ++ desktopModules;
    };
    nixie = nixosSystem {
      modules =
        [
          ./nixie
          ../modules/bluetooth.nix
          ../modules/virtualization.nix
          ../modules/atuin.nix
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixie";}
          inputs.hardware.nixosModules.common-pc
          inputs.hardware.nixosModules.common-pc-ssd
          inputs.hardware.nixosModules.common-cpu-intel
        ]
        ++ sharedModules;
    };
  };
}
