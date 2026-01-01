{
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
    settings = {
      signs = {
        add = {text = "+";};
        change = {text = "~";};
        delete = {text = "_";};
        topdelete = {text = "‾";};
        changedelete = {text = "~";};
      };
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
          __unkeyed-1 = "<leader>c";
          group = "[C]ode";
          mode = ["n" "x"];
        }
        {
          __unkeyed-1 = "<leader>d";
          group = "[D]ocument";
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
          __unkeyed-1 = "<leader>w";
          group = "[W]orkspace";
        }
        {
          __unkeyed-1 = "<leader>t";
          group = "[T]oggle";
        }
        {
          __unkeyed-1 = "<leader>h";
          group = "Git [H]unk";
          mode = ["n" "v"];
        }
      ];
    };
  };

  # TODO comments highlighting
  plugins.todo-comments = {
    enable = true;
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
