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
    ./ghostty.nix
    ./syncthing.nix
  ];

  programs = {
    chromium = {
      enable = true;
    };

    firefox = {
      enable = true;
    };
  };

  home.packages = [
    pkgs.obsidian
    # pkgs.bruno
    pkgs.websocat
    pkgs.google-chrome
  ];

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
