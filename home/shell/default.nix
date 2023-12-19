{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./atuin.zsh
    ./cli.zsh
    ./zsh.zsh
    ./starship.zsh
  ];

  home.sessionVariables = {
    LESSHISTFILE = "${config.xdg.cacheHome}/less/history";
    LESSKEY = "${config.xdg.configHome}/less/lesskey";

    EDITOR = "nvim";
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
    DIRENV_LOG_FORMAT = "";

    # auto-run programs using nix-index-database
    NIX_AUTO_RUN = "1";
  };
}
