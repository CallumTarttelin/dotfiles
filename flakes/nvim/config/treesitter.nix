{
  plugins.treesitter = {
    enable = true;

    settings = {
      highlight = {
        enable = true;
        # Some languages depend on vim's regex highlighting for indent rules
        additional_vim_regex_highlighting = ["ruby"];
      };

      indent = {
        enable = true;
        disable = ["ruby"];
      };
    };
  };
}
