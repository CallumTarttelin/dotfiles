# Wraps the existing nvim flake output as a package.
# TODO: Move nixvim config in-repo once nixvim API compat is resolved.
{
  inputs,
  self,
  ...
}: {
  perSystem = {system, ...}: {
    packages.myNeovim = inputs.nvim.packages.${system}.default;
  };

  flake.nixosModules.neovim = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.myNeovim
    ];
  };
}
