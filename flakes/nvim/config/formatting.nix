{pkgs, ...}: {
  plugins.conform-nvim = {
    enable = true;

    settings = {
      notify_on_error = false;

      formatters_by_ft = {
        lua = ["stylua"];
        nix = ["alejandra"];
      };

      format_on_save = {
        timeout_ms = 500;
        lsp_format = "fallback";
      };
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

  # Formatters need to be available
  extraPackages = with pkgs; [
    stylua
    alejandra
  ];
}
