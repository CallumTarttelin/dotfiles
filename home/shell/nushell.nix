_: {
  programs.nushell = {
    enable = true;

    shellAliases = {
      grep = "grep --color";
      ip = "ip --color";
      icat = "wezterm imgcat";
      us = "systemctl --user";
      rs = "sudo systemctl";
      cat = "bat";
    };
  };
}
