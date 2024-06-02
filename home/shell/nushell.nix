{
  config,
  lib,
  ...
}: {
  programs.nushell = {
    enable = true;

    shellAliases =
      {
        grep = "grep --color";
        ip = "ip --color";

        icat = "wezterm imgcat";

        us = "systemctl --user";
        rs = "sudo systemctl";
      }
      // lib.optionalAttrs (config.programs.bat.enable == true) {cat = "bat";};
  };
}
