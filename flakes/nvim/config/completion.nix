{
  plugins.luasnip = {
    enable = true;
    fromVscode = [{}]; # Load friendly-snippets
  };

  plugins.cmp = {
    enable = true;
    autoEnableSources = true;

    settings = {
      snippet = {
        expand = ''
          function(args)
            require('luasnip').lsp_expand(args.body)
          end
        '';
      };

      completion = {
        completeopt = "menu,menuone,noinsert";
      };

      sources = [
        {name = "nvim_lsp";}
        {name = "luasnip";}
        {name = "path";}
        {name = "nvim_lsp_signature_help";}
      ];

      mapping = {
        # Select next/previous item
        "<C-n>" = "cmp.mapping.select_next_item()";
        "<C-p>" = "cmp.mapping.select_prev_item()";

        # Scroll documentation
        "<C-b>" = "cmp.mapping.scroll_docs(-4)";
        "<C-f>" = "cmp.mapping.scroll_docs(4)";

        # Accept completion
        "<C-y>" = "cmp.mapping.confirm({ select = true })";

        # Manually trigger completion
        "<C-Space>" = "cmp.mapping.complete()";

        # Snippet navigation
        "<C-l>" = ''
          cmp.mapping(function()
            local luasnip = require('luasnip')
            if luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            end
          end, { 'i', 's' })
        '';
        "<C-h>" = ''
          cmp.mapping(function()
            local luasnip = require('luasnip')
            if luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            end
          end, { 'i', 's' })
        '';
      };
    };
  };
}
