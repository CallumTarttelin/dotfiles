{pkgs, ...}: {
  home.packages = with pkgs; [
    jetbrains.idea-ultimate
    jetbrains.rust-rover
    jetbrains.webstorm
    jetbrains.pycharm-professional
    jetbrains-toolbox
  ];

  programs.vscode = {
    enable = true;
    extensions = with pkgs; [
      vscode-extensions.vscodevim.vim
    ];
  };
}
