{self, ...}: {
  flake.nixosModules.neovim = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.nvim
    ];
  };
}
