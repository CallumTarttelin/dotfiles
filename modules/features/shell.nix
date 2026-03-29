{self, ...}: {
  flake.nixosModules.shell = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.features.shell;
    inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) myZsh;
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

      # Ghostty terminfo so SSH sessions from Ghostty terminals work correctly
      environment.systemPackages = [pkgs.ghostty.terminfo];

      home-manager.users.tarttelin = {
        # ssh-agent as a systemd user service — socket available to all user sessions
        services.ssh-agent.enable = true;
      };
    };
  };
}
