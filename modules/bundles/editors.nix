{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.editors = pkgs.buildEnv {
      name = "editors";
      paths = with pkgs; [
        jetbrains.idea
        jetbrains.rust-rover
        jetbrains.clion
        zed-editor
      ];
    };
  };

  flake.nixosModules.editors = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.editors
    ];
  };
}
