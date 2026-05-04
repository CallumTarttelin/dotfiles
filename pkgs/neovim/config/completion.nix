{
  plugins.blink-cmp = {
    enable = true;

    settings = {
      keymap = {
        preset = "none";
        "<C-n>" = ["select_next" "fallback"];
        "<C-p>" = ["select_prev" "fallback"];
        "<C-b>" = ["scroll_documentation_up" "fallback"];
        "<C-f>" = ["scroll_documentation_down" "fallback"];
        "<C-y>" = ["accept" "fallback"];
        "<C-Space>" = ["show" "show_documentation" "hide_documentation"];
        "<C-l>" = ["snippet_forward" "fallback"];
        "<C-h>" = ["snippet_backward" "fallback"];
      };

      completion = {
        accept = {
          auto_brackets.enabled = true;
        };
        documentation = {
          auto_show = true;
          auto_show_delay_ms = 200;
        };
        list.selection = {
          preselect = true;
          auto_insert = true;
        };
        menu.draw = {
          columns = [
            {__unkeyed-1 = "kind_icon";}
            {
              __unkeyed-1 = "label";
              __unkeyed-2 = "label_description";
              gap = 1;
            }
            {__unkeyed-1 = "kind";}
          ];
        };
      };

      signature = {
        enabled = true;
      };

      sources = {
        default = ["lsp" "path" "snippets" "buffer"];
      };

      snippets = {
        preset = "default";
      };
    };
  };

  # Friendly snippets for common language snippets
  plugins.friendly-snippets.enable = true;
}
