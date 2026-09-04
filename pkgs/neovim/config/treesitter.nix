{
  config,
  pkgs,
  ...
}: {
  plugins.treesitter = {
    enable = true;
    grammarPackages =
      config.plugins.treesitter.package.allGrammars
      ++ [
        pkgs.tree-sitter-grammars.tree-sitter-lean
      ];
    indent.disable = ["ruby"];

    settings = {
      highlight = {
        enable = true;
        # Some languages depend on vim's regex highlighting for indent rules
        additional_vim_regex_highlighting = ["ruby"];
      };

      indent = {
        enable = true;
      };
    };
  };
}
