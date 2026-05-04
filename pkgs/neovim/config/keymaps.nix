{
  # Global keymaps
  keymaps = [
    # Clear search highlights
    {
      mode = "n";
      key = "<Esc>";
      action = "<cmd>nohlsearch<CR>";
    }

    # Diagnostic quickfix list
    {
      mode = "n";
      key = "<leader>q";
      action.__raw = "vim.diagnostic.setloclist";
      options.desc = "Open diagnostic [Q]uickfix list";
    }

    # Show diagnostic in floating window
    {
      mode = "n";
      key = "<leader>e";
      action.__raw = "vim.diagnostic.open_float";
      options.desc = "Show diagnostic [E]rror messages";
    }

    # Exit terminal mode
    {
      mode = "t";
      key = "<Esc><Esc>";
      action = "<C-\\><C-n>";
      options.desc = "Exit terminal mode";
    }

    # Window navigation
    {
      mode = "n";
      key = "<C-h>";
      action = "<C-w><C-h>";
      options.desc = "Move focus to the left window";
    }
    {
      mode = "n";
      key = "<C-l>";
      action = "<C-w><C-l>";
      options.desc = "Move focus to the right window";
    }
    {
      mode = "n";
      key = "<C-j>";
      action = "<C-w><C-j>";
      options.desc = "Move focus to the lower window";
    }
    {
      mode = "n";
      key = "<C-k>";
      action = "<C-w><C-k>";
      options.desc = "Move focus to the upper window";
    }
  ];

  # Autocommands
  autoCmd = [
    # Highlight when yanking text
    {
      event = "TextYankPost";
      desc = "Highlight when yanking (copying) text";
      group = "kickstart-highlight-yank";
      callback.__raw = ''
        function()
          vim.highlight.on_yank()
        end
      '';
    }
  ];

  autoGroups = {
    "kickstart-highlight-yank" = {clear = true;};
  };
}
