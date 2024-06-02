{
  lib,
  pkgs,
  ...
}: let
  dconf = "${pkgs.dconf}/bin/dconf";

  dconfDark = ''${dconf} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"'';
in {
  imports = [
    ./neovim.nix
    ./foot.nix
    ./wezterm.nix
  ];

  programs = {
    chromium = {
      enable = true;
    };

    firefox = {
      enable = true;
    };
  };

  # set dark as default theme
  systemd.user.services.dconf-dark = {
    Unit = {
      Description = "Set dconf to be dark mode";
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = dconfDark;
      Restart = "on-failure";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
