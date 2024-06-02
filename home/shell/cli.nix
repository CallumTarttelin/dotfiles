{
  pkgs,
  config,
  ...
}: {
  home.packages = with pkgs; [
    zip
    unzip

    du-dust
    duf
    fd
    file
    jq
    ripgrep
    htop
    killall
    nushell
  ];

  programs = {
    bat.enable = true;
    btop.enable = true;
    zoxide = {
      enable = true;
      enableZshIntegration = true;
      enableNushellIntegration = true;
    };
    eza = {
      enable = true;
      icons = true;
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
