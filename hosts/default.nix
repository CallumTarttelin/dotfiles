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
          ({pkgs, ...}: let
            selfpkgs = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
          in {
            features = {
              desktop.enable = true;
              hyprland-desktop = {
                enable = true;
                desktopShell = "noctalia";
                noctaliaPackage = selfpkgs.myNoctalia-nixshark;
                monitors = [
                  "DP-1,preferred,1920x0,1,vrr,1"
                  "HDMI-A-1,preferred,4480x0,1"
                  "DP-2,preferred,0x0,1"
                  ",preferred,auto,1"
                ];
              };
              logiops.enable = true;
              bluetooth.enable = true;
              security.yubikey = true;
              gaming.enable = true;
              virtualization.enable = true;
              shell.enable = true;
            };
            bundles = {
              go-tools.enable = true;
              jvm-tools.enable = true;
              web-tools.enable = true;
              python-tools.enable = true;
              beam-tools.enable = true;
              infra-tools.enable = true;
              build-tools.enable = true;
              rust-tools.enable = true;
              nix-tools.enable = true;
            };
          })
        ]
        ++ allModules;
    };
    nixwork = nixosSystem {
      modules =
        [
          ./nixwork
          {home-manager.users.tarttelin.imports = homeImports."tarttelin@nixwork";}
          inputs.hardware.nixosModules.framework-13-7040-amd
          ({pkgs, ...}: let
            selfpkgs = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
          in {
            features = {
              desktop.enable = true;
              hyprland-desktop = {
                enable = true;
                desktopShell = "noctalia";
                noctaliaPackage = selfpkgs.myNoctalia-nixwork;
                monitors = ["eDP-1,preferred,auto,1"];
              };
              logiops.enable = true;
              bluetooth.enable = true;
              security.yubikey = true;
              virtualization.enable = true;
              shell.enable = true;
            };
            bundles = {
              go-tools.enable = true;
              jvm-tools.enable = true;
              web-tools.enable = true;
              python-tools.enable = true;
              beam-tools.enable = true;
              infra-tools.enable = true;
              build-tools.enable = true;
              rust-tools.enable = true;
              nix-tools.enable = true;
            };
          })
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
              binary-cache.enable = true;
              bluetooth.enable = true;
              virtualization.enable = true;
              atuin-server.enable = true;
              shell.enable = true;
            };
            bundles.nix-tools.enable = true;
          }
        ]
        ++ allModules;
    };
  };
}
