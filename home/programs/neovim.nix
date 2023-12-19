{pkgs, ...}: {
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
  };

  home.packages = with pkgs; [
    # Add LSPs
    nil
    gopls
    # Rust language server installed separately with rust config
    clang-tools
    nodePackages.pyright
    typescript
    #      java-language-server
    kotlin-language-server
  ];
}
