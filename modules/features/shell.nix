{self, ...}: {
  flake.nixosModules.shell = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.features.shell;
  in {
    options.features.shell = {
      enable = lib.mkEnableOption "Custom wrapped shell as default";
    };

    config = lib.mkIf cfg.enable {
      users.users.tarttelin.shell = self.packages.${pkgs.stdenv.hostPlatform.system}.myZsh;
      programs.zsh.enable = true; # needed for /etc/shells
    };
  };
}
