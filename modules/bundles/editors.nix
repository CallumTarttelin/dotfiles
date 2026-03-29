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

  flake.nixosModules.editors = {config, lib, pkgs, ...}: {
    options.bundles.editors.enable = lib.mkEnableOption "GUI editors (IntelliJ, Rust-Rover, CLion, Zed)";
    config = lib.mkIf config.bundles.editors.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.editors
      ];
    };
  };
}
