{
  pkgs,
  config,
  ...
}: {
  home.packages = with pkgs; [
    zip
    unzip

    dust
    duf
    fd
    file
    jq
    ripgrep
    htop
    killall
    nushell
    glow
    zellij
    jujutsu
    lazyjj
    jjui

    lsof

    git-agecrypt
    git-credential-keepassxc

    openssl
  ];

  programs = {
    tmux = {
      enable = true;
      terminal = "xterm-ghostty";
    };
    yazi = {
      enable = true;
      shellWrapperName = "y";
      settings.manager = {
        show_hidden = true;
        show_symlink = true;
      };
    };
    bat.enable = true;
    btop.enable = true;
    zoxide = {
      enable = true;
      enableZshIntegration = true;
      enableNushellIntegration = true;
    };
    eza = {
      enable = true;
      icons = "auto";
      git = true;
      enableNushellIntegration = true;
    };
    skim = {
      enable = true;
      enableZshIntegration = true;
      defaultCommand = "fd --type f";
      fileWidgetCommand = "fd --type f";
      changeDirWidgetCommand = "fd --type d";
      changeDirWidgetOptions = [
        "--preview 'eza --icons --git --color always -T -L 3 {} | head -200'"
        "--exact"
      ];
    };
  };
}
