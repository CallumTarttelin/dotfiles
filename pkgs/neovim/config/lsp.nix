{
  plugins.lsp = {
    enable = true;

    # Lazy load LSP on filetypes that have servers configured
    lazyLoad.settings.ft = [
      "lua"
      "c"
      "cpp"
      "python"
      "rust"
      "go"
      "bash"
      "sh"
      "nix"
      "java"
      "kotlin"
      "typescript"
      "javascript"
      "typescriptreact"
      "javascriptreact"
    ];

    keymaps = {
      # Diagnostic keymaps are set in keymaps.nix

      lspBuf = {
        "gd" = {
          action = "definition";
          desc = "LSP: [G]oto [D]efinition";
        };
        "gr" = {
          action = "references";
          desc = "LSP: [G]oto [R]eferences";
        };
        "gI" = {
          action = "implementation";
          desc = "LSP: [G]oto [I]mplementation";
        };
        "<leader>D" = {
          action = "type_definition";
          desc = "LSP: Type [D]efinition";
        };
        "<leader>rn" = {
          action = "rename";
          desc = "LSP: [R]e[n]ame";
        };
        "<leader>ca" = {
          action = "code_action";
          desc = "LSP: [C]ode [A]ction";
        };
        "gD" = {
          action = "declaration";
          desc = "LSP: [G]oto [D]eclaration";
        };
      };

      extra = [
        {
          mode = "n";
          key = "<leader>ds";
          action.__raw = "require('telescope.builtin').lsp_document_symbols";
          options.desc = "LSP: [D]ocument [S]ymbols";
        }
        {
          mode = "n";
          key = "<leader>ws";
          action.__raw = "require('telescope.builtin').lsp_dynamic_workspace_symbols";
          options.desc = "LSP: [W]orkspace [S]ymbols";
        }
        {
          mode = "n";
          key = "<leader>th";
          action.__raw = ''
            function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
            end
          '';
          options.desc = "LSP: [T]oggle Inlay [H]ints";
        }
      ];
    };

    servers = {
      lua_ls = {
        enable = true;
        settings = {
          Lua = {
            completion = {
              callSnippet = "Replace";
            };
          };
        };
      };
      clangd.enable = true;
      ty.enable = true;
      rust_analyzer = {
        enable = true;
        installCargo = false;
        installRustc = false;
      };
      gopls.enable = true;
      bashls.enable = true;
      nil_ls.enable = true;
      java_language_server.enable = true;
      kotlin_language_server.enable = true;
      ts_ls.enable = true;
    };
  };

  # Fidget for LSP progress notifications
  plugins.fidget = {
    enable = true;
    lazyLoad.settings.event = "LspAttach";
  };
}
