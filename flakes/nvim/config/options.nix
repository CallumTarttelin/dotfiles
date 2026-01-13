{
  # Enable lazy loading provider
  plugins.lz-n.enable = true;

  # Leader key
  globals = {
    mapleader = " ";
    maplocalleader = " ";
    have_nerd_font = false;
  };

  # Vim options
  opts = {
    # Line numbers
    number = true;

    # Enable mouse mode
    mouse = "a";

    # Don't show mode (already in statusline)
    showmode = false;

    # Sync clipboard with OS
    clipboard = "unnamedplus";

    # Enable break indent
    breakindent = true;

    # Save undo history
    undofile = true;

    # Case-insensitive searching unless \C or capital letters
    ignorecase = true;
    smartcase = true;

    # Keep signcolumn on by default
    signcolumn = "yes";

    # Decrease update time
    updatetime = 250;

    # Decrease mapped sequence wait time
    timeoutlen = 300;

    # Configure split behavior
    splitright = true;
    splitbelow = true;

    # Whitespace display
    list = true;
    listchars = {
      tab = "» ";
      trail = "·";
      nbsp = "␣";
    };

    # Preview substitutions live
    inccommand = "split";

    # Highlight cursor line
    cursorline = true;

    # Keep lines above/below cursor
    scrolloff = 10;
  };
}
