{
  # Snacks.nvim - collection of utilities
  plugins.snacks = {
    enable = true;
    settings = {
      # Better handling of big files
      bigfile.enabled = true;

      # Indent guides - subtle, scope only
      indent = {
        enabled = true;
        char = " ";
        only_scope = true;
        scope = {
          enabled = false;
          char = "│";
        };
        blank = {
          char = " ";
        };
      };

      # Quick file opening (skip intro for files from cmdline)
      quickfile.enabled = true;

      # Highlight word under cursor
      words = {
        enabled = true;
        debounce = 200;
      };

      # Better vim.ui.input
      input.enabled = true;

      # Status column with signs, line numbers, folds
      statuscolumn.enabled = true;

      # Scope detection
      scope.enabled = true;

      # Dashboard disabled (can enable if you want a start screen)
      dashboard.enabled = false;
    };
  };

  # File explorer (edit directories like buffers)
  plugins.oil = {
    enable = true;
    settings = {
      default_file_explorer = true;
      delete_to_trash = true;
      skip_confirm_for_simple_edits = true;
      view_options = {
        show_hidden = true;
        natural_order = true;
      };
      keymaps = {
        "g?" = "actions.show_help";
        "<CR>" = "actions.select";
        "<C-v>" = "actions.select_vsplit";
        "<C-s>" = "actions.select_split";
        "<C-t>" = "actions.select_tab";
        "<C-p>" = "actions.preview";
        "<C-c>" = "actions.close";
        "<C-r>" = "actions.refresh";
        "-" = "actions.parent";
        "_" = "actions.open_cwd";
        "`" = "actions.cd";
        "~" = "actions.tcd";
        "gs" = "actions.change_sort";
        "gx" = "actions.open_external";
        "g." = "actions.toggle_hidden";
        "g\\" = "actions.toggle_trash";
      };
    };
  };

  # Keymaps for oil and snacks
  keymaps = [
    # Oil
    {
      mode = "n";
      key = "-";
      action = "<cmd>Oil<CR>";
      options.desc = "Open parent directory";
    }
    # Snacks
    {
      mode = "n";
      key = "<leader>nh";
      action.__raw = "function() Snacks.notifier.hide() end";
      options.desc = "[N]otifications [H]ide";
    }
    {
      mode = "n";
      key = "<leader>nn";
      action.__raw = "function() Snacks.notifier.show_history() end";
      options.desc = "[N]otification history";
    }
    {
      mode = "n";
      key = "<leader>bd";
      action.__raw = "function() Snacks.bufdelete() end";
      options.desc = "[B]uffer [D]elete";
    }
    {
      mode = "n";
      key = "<leader>gg";
      action.__raw = "function() Snacks.lazygit() end";
      options.desc = "Lazygit";
    }
    {
      mode = "n";
      key = "]]";
      action.__raw = "function() Snacks.words.jump(vim.v.count1) end";
      options.desc = "Next reference";
    }
    {
      mode = "n";
      key = "[[";
      action.__raw = "function() Snacks.words.jump(-vim.v.count1) end";
      options.desc = "Previous reference";
    }
  ];

  # Colorscheme
  colorschemes.tokyonight = {
    enable = true;
    settings = {
      style = "night";
    };
  };

  # Git signs in gutter
  plugins.gitsigns = {
    enable = true;
    lazyLoad.settings.event = "BufReadPost";
    settings = {
      signs = {
        add = {text = "+";};
        change = {text = "~";};
        delete = {text = "_";};
        topdelete = {text = "‾";};
        changedelete = {text = "~";};
      };
      on_attach.__raw = ''
        function(bufnr)
          local gitsigns = require('gitsigns')

          local function map(mode, l, r, opts)
            opts = opts or {}
            opts.buffer = bufnr
            vim.keymap.set(mode, l, r, opts)
          end

          -- Navigation
          map('n', ']c', function()
            if vim.wo.diff then
              vim.cmd.normal({']c', bang = true})
            else
              gitsigns.nav_hunk('next')
            end
          end, {desc = 'Next hunk'})

          map('n', '[c', function()
            if vim.wo.diff then
              vim.cmd.normal({'[c', bang = true})
            else
              gitsigns.nav_hunk('prev')
            end
          end, {desc = 'Previous hunk'})

          -- Actions under <leader>g
          map('n', '<leader>gs', gitsigns.stage_hunk, {desc = '[G]it [S]tage hunk'})
          map('n', '<leader>gr', gitsigns.reset_hunk, {desc = '[G]it [R]eset hunk'})
          map('v', '<leader>gs', function() gitsigns.stage_hunk {vim.fn.line('.'), vim.fn.line('v')} end, {desc = '[G]it [S]tage hunk'})
          map('v', '<leader>gr', function() gitsigns.reset_hunk {vim.fn.line('.'), vim.fn.line('v')} end, {desc = '[G]it [R]eset hunk'})
          map('n', '<leader>gS', gitsigns.stage_buffer, {desc = '[G]it [S]tage buffer'})
          map('n', '<leader>gu', gitsigns.undo_stage_hunk, {desc = '[G]it [U]ndo stage hunk'})
          map('n', '<leader>gR', gitsigns.reset_buffer, {desc = '[G]it [R]eset buffer'})
          map('n', '<leader>gp', gitsigns.preview_hunk, {desc = '[G]it [P]review hunk'})
          map('n', '<leader>gb', function() gitsigns.blame_line{full=true} end, {desc = '[G]it [B]lame line'})
          map('n', '<leader>gB', function() gitsigns.blame() end, {desc = '[G]it [B]lame file'})
          map('n', '<leader>gd', gitsigns.diffthis, {desc = '[G]it [D]iff this'})
          map('n', '<leader>gD', function() gitsigns.diffthis('~') end, {desc = '[G]it [D]iff against ~'})

          -- Toggles
          map('n', '<leader>tb', function() gitsigns.toggle_current_line_blame() end, {desc = '[T]oggle line [B]lame'})
          map('n', '<leader>td', function() gitsigns.toggle_deleted() end, {desc = '[T]oggle [D]eleted'})

          -- Text object
          map({'o', 'x'}, 'ih', ':<C-U>Gitsigns select_hunk<CR>', {desc = 'Select hunk'})
        end
      '';
    };
  };

  # Which-key for pending keybinds popup
  plugins.which-key = {
    enable = true;
    settings = {
      delay = 0;
      icons = {
        mappings = false; # No nerd font
        keys = {
          Up = "<Up> ";
          Down = "<Down> ";
          Left = "<Left> ";
          Right = "<Right> ";
          C = "<C-…> ";
          M = "<M-…> ";
          D = "<D-…> ";
          S = "<S-…> ";
          CR = "<CR> ";
          Esc = "<Esc> ";
          ScrollWheelDown = "<ScrollWheelDown> ";
          ScrollWheelUp = "<ScrollWheelUp> ";
          NL = "<NL> ";
          BS = "<BS> ";
          Space = "<Space> ";
          Tab = "<Tab> ";
          F1 = "<F1>";
          F2 = "<F2>";
          F3 = "<F3>";
          F4 = "<F4>";
          F5 = "<F5>";
          F6 = "<F6>";
          F7 = "<F7>";
          F8 = "<F8>";
          F9 = "<F9>";
          F10 = "<F10>";
          F11 = "<F11>";
          F12 = "<F12>";
        };
      };
      spec = [
        {
          __unkeyed-1 = "<leader>b";
          group = "[B]uffer";
        }
        {
          __unkeyed-1 = "<leader>c";
          group = "[C]ode";
          mode = ["n" "x"];
        }
        {
          __unkeyed-1 = "<leader>g";
          group = "[G]it";
          mode = ["n" "v"];
        }
        {
          __unkeyed-1 = "<leader>n";
          group = "[N]otifications";
        }
        {
          __unkeyed-1 = "<leader>r";
          group = "[R]ename";
        }
        {
          __unkeyed-1 = "<leader>s";
          group = "[S]earch";
        }
        {
          __unkeyed-1 = "<leader>t";
          group = "[T]oggle";
        }
        {
          __unkeyed-1 = "<leader>w";
          group = "[W]orkspace";
        }
      ];
    };
  };

  # TODO comments highlighting
  plugins.todo-comments = {
    enable = true;
    lazyLoad.settings.event = "BufReadPost";
    settings = {
      signs = false;
    };
  };

  # Auto-detect indentation
  plugins.sleuth.enable = true;

  # Mini.nvim modules
  plugins.mini = {
    enable = true;
    modules = {
      # Better Around/Inside textobjects
      ai = {
        n_lines = 500;
      };

      # Add/delete/replace surroundings
      surround = {};

      # Simple statusline
      statusline = {
        use_icons = false; # No nerd font
      };
    };
  };

  # Web devicons disabled (no nerd font)
  plugins.web-devicons.enable = false;
}
