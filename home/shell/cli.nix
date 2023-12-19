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
  ];

  programs = {
    bat.enable = true;
    btop.enable = true;
    eza.enable = true;
    skim = {
      enable = true;
      enableZshIntegration = true;
      defaultCommand = "rg --files --hidden";
      changeDirWidgetOptions = [
        "--preview 'eza --icons --git --color always -T -L 3 {} | head -200'"
        "--exact"
      ];
    };
  };
}
