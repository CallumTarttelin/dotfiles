{
  lib,
  pkgs,
  ...
}: {
  programs.neovim = {
    enable = true;
    viAlias = cfg.aliases;
    vimAlias = cfg.aliases;
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
