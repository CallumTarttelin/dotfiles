{config, ...}: {
  imports = [
    # zsh, cli, atuin, starship replaced by wrapped packages
    ./nushell.nix
    ./nix.nix
  ];

  home.sessionVariables = {
    LESSHISTFILE = "${config.xdg.cacheHome}/less/history";
    LESSKEY = "${config.xdg.configHome}/less/lesskey";
    DIRENV_LOG_FORMAT = "";
  };
}
