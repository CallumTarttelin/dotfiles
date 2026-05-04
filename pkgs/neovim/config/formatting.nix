{pkgs, ...}: {
  plugins.conform-nvim = {
    enable = true;
    lazyLoad.settings = {
      event = ["BufWritePre"];
      keys = ["<leader>f"];
    };

    settings = {
      notify_on_error = false;

      formatters_by_ft = {
        lua = ["stylua"];
        nix = ["alejandra"];
        go = ["goimports" "gofumpt"];
        python = ["ruff_format" "ruff_organize_imports"];
        rust = ["rustfmt"];
        typescript = ["prettierd"];
        javascript = ["prettierd"];
        typescriptreact = ["prettierd"];
        javascriptreact = ["prettierd"];
        json = ["prettierd"];
        yaml = ["prettierd"];
        markdown = ["prettierd"];
        html = ["prettierd"];
        css = ["prettierd"];
        kotlin = ["ktlint"];
        sh = ["shfmt"];
        bash = ["shfmt"];
        zsh = ["shfmt"];
        toml = ["taplo"];
      };

      format_on_save = {
        timeout_ms = 500;
        lsp_format = "fallback";
      };

      # Formatter-specific settings
      formatters = {
        shfmt = {
          prepend_args = ["-i" "2" "-ci"];
        };
      };
    };
  };

  # nvim-lint for linting
  plugins.lint = {
    enable = true;
    lazyLoad.settings = {
      event = ["BufWritePost" "BufReadPost" "InsertLeave"];
    };
    lintersByFt = {
      go = ["golangcilint"];
      python = ["ruff"];
      nix = ["statix"];
      sh = ["shellcheck"];
      bash = ["shellcheck"];
      typescript = ["eslint_d"];
      javascript = ["eslint_d"];
      typescriptreact = ["eslint_d"];
      javascriptreact = ["eslint_d"];
      kotlin = ["ktlint"];
    };
    autoCmd = {
      event = ["BufWritePost" "BufReadPost" "InsertLeave"];
      callback.__raw = ''
        function()
          require('lint').try_lint()
        end
      '';
    };
  };

  # Format keymap
  keymaps = [
    {
      mode = "";
      key = "<leader>f";
      action.__raw = ''
        function()
          require('conform').format({ async = true, lsp_format = 'fallback' })
        end
      '';
      options.desc = "[F]ormat buffer";
    }
  ];

  # Formatters, linters, and tools
  extraPackages = with pkgs; [
    # Lua
    stylua
    # Nix
    alejandra
    statix
    # Go
    gofumpt
    goimports-reviser
    gotools # goimports
    golangci-lint
    # Python
    ruff
    ty
    # JS/TS
    prettierd
    eslint_d
    # Kotlin
    ktlint
    # Rust
    rustfmt
    # Shell
    shfmt
    shellcheck
    # TOML
    taplo
    # Git
    lazygit
  ];
}
