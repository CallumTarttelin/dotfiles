{
  inputs,
  withSystem,
  module_args,
  ...
}: let
  sharedModules = [
    module_args
    ../.
    ../programs
    ../shell
    ../xdg.nix
  ];

  homeImports = {
    "tarttelin@nixshark" = [./nixshark] ++ sharedModules;
    "tarttelin@nixwork" = [./nixwork] ++ sharedModules;
    "tarttelin@nixie" = [./nixie] ++ sharedModules;
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
      "tarttelin@nixie" = homeManagerConfiguration {
        modules = homeImports."tarttelin@nixie";
        inherit pkgs;
      };
    });
  };
}
