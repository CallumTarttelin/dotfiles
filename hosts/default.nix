{
  inputs,
  allModules,
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
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixshark";}
          inputs.hardware.nixosModules.common-pc
          inputs.hardware.nixosModules.common-pc-ssd
          inputs.hardware.nixosModules.common-cpu-amd
          inputs.hardware.nixosModules.common-cpu-amd-pstate
          inputs.hardware.nixosModules.common-gpu-amd
          {
            features = {
              desktop.enable = true;
              greeter.enable = true;
              logiops.enable = true;
              bluetooth.enable = true;
              yubikey.enable = true;
              gaming.enable = true;
              virtualization.enable = true;
              shell.enable = true;
            };
          }
        ]
        ++ allModules;
    };
    nixwork = nixosSystem {
      modules =
        [
          ./nixwork
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixwork";}
          inputs.hardware.nixosModules.framework-13-7040-amd
          {
            features = {
              desktop.enable = true;
              greeter.enable = true;
              logiops.enable = true;
              bluetooth.enable = true;
              yubikey.enable = true;
              virtualization.enable = true;
              shell.enable = true;
            };
          }
        ]
        ++ allModules;
    };
    nixie = nixosSystem {
      modules =
        [
          ./nixie
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixie";}
          inputs.hardware.nixosModules.common-pc
          inputs.hardware.nixosModules.common-pc-ssd
          inputs.hardware.nixosModules.common-cpu-intel
          {
            features = {
              bluetooth.enable = true;
              virtualization.enable = true;
              atuin-server.enable = true;
              shell.enable = true;
            };
          }
        ]
        ++ allModules;
    };
  };
}
