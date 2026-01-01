{
  plugins.telescope = {
    enable = true;

    extensions = {
      fzf-native.enable = true;
      ui-select.enable = true;
    };

    keymaps = {
      "<leader>sh" = {
        action = "help_tags";
        options.desc = "[S]earch [H]elp";
      };
      "<leader>sk" = {
        action = "keymaps";
        options.desc = "[S]earch [K]eymaps";
      };
      "<leader>sf" = {
        action = "find_files";
        options.desc = "[S]earch [F]iles";
      };
      "<leader>ss" = {
        action = "builtin";
        options.desc = "[S]earch [S]elect Telescope";
      };
      "<leader>sw" = {
        action = "grep_string";
        options.desc = "[S]earch current [W]ord";
      };
      "<leader>sg" = {
        action = "live_grep";
        options.desc = "[S]earch by [G]rep";
      };
      "<leader>sd" = {
        action = "diagnostics";
        options.desc = "[S]earch [D]iagnostics";
      };
      "<leader>sr" = {
        action = "resume";
        options.desc = "[S]earch [R]esume";
      };
      "<leader>s." = {
        action = "oldfiles";
        options.desc = "[S]earch Recent Files";
      };
      "<leader><leader>" = {
        action = "buffers";
        options.desc = "Find existing buffers";
      };
    };

    settings = {
      extensions = {
        ui-select = {
          __raw = "require('telescope.themes').get_dropdown()";
        };
      };
    };
  };

  # Additional telescope keymaps via extraConfigLua
  extraConfigLua = ''
    -- Fuzzy search in current buffer
    vim.keymap.set('n', '<leader>/', function()
      require('telescope.builtin').current_buffer_fuzzy_find(
        require('telescope.themes').get_dropdown({
          winblend = 10,
          previewer = false,
        })
      )
    end, { desc = '[/] Fuzzily search in current buffer' })

    -- Live grep in open files
    vim.keymap.set('n', '<leader>s/', function()
      require('telescope.builtin').live_grep({
        grep_open_files = true,
        prompt_title = 'Live Grep in Open Files',
      })
    end, { desc = '[S]earch [/] in Open Files' })

    -- Search neovim config files
    vim.keymap.set('n', '<leader>sn', function()
      require('telescope.builtin').find_files({ cwd = vim.fn.stdpath('config') })
    end, { desc = '[S]earch [N]eovim files' })
  '';
}
