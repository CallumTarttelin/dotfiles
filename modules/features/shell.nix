{self, ...}: {
  flake.nixosModules.shell = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.features.shell;
    myZsh = self.packages.${pkgs.stdenv.hostPlatform.system}.myZsh;
  in {
    options.features.shell = {
      enable = lib.mkEnableOption "Custom wrapped shell as default";
    };

    config = lib.mkIf cfg.enable {
      # Use the full store path directly to avoid NixOS normalising it
      # to /run/current-system/sw/bin/zsh (which would be the bare zsh)
      users.users.tarttelin.shell = lib.mkForce "${myZsh}/bin/zsh";
      programs.zsh.enable = true;
      environment.shells = ["${myZsh}/bin/zsh"];
    };
  };
}
