{self, ...}: {
  flake.nixosModules.shell = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.features.shell;
    inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) localproxy myZsh;
  in {
    options.features.shell = {
      enable = lib.mkEnableOption "Custom wrapped shell as default";
      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["tarttelin"];
        description = "Users that should use the custom wrapped shell.";
      };
    };

    config = lib.mkIf cfg.enable {
      # Use the full store path directly to avoid NixOS normalising it
      # to /run/current-system/sw/bin/zsh (which would be the bare zsh)
      users.users = lib.genAttrs cfg.users (_: {
        shell = lib.mkForce "${myZsh}/bin/zsh";
      });
      programs.zsh.enable = true;
      environment.shells = ["${myZsh}/bin/zsh"];

      # Ghostty terminfo so SSH sessions from Ghostty terminals work correctly
      environment.systemPackages = [pkgs.ghostty.terminfo];

      home-manager.users = lib.genAttrs cfg.users (_: {
        # ssh-agent as a systemd user service — socket available to all user sessions
        services.ssh-agent.enable = true;
        home.packages = [localproxy];
      });
    };
  };
}
