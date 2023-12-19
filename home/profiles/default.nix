{
  inputs,
  withSystem,
  ...
}: let
  sharedModules = [
    ../.
    ../programs
    ../shell
    ../xdg.nix
  ];

  homeImports = {
    "tarttelin@nixshark" = [./nixshark] ++ sharedModules;
    "tarttelin@nixwork" = [./nixwork] ++ sharedModules;
  };

  inherit (inputs.hm.lib) homeManagerConfiguration;
in {
  imports = [
    {_module.args = {inherit homeImports;};}
  ];

  flake = {
    homeConfigurations = withSystem "x86_64-linux" ({pkgs, ...}: {
      "tarttelin@nixshark" = homeManagerConfiguration {
        modules = homeImports."tarttelin@nixshark";
        inherit pkgs;
      };
      "tarttelin@nixwork" = homeManagerConfiguration {
        modules = homeImports."tarttelin@nixwork";
        inherit pkgs;
      };
    });
  };
}
