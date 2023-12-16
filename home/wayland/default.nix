{
  pkgs,
  lib,
  self,
  inputs,
  config,
  ...
}: {
  imports = [
    ./hyprland.nix
    ./hyprpaper.nix
    ./idle.nix
  ];

  home.packages = with pkgs; [
    # screenshot
    grim
    slurp
    waybar

    # utils
    wl-clipboard
    wl-screenrec
  ];

  # make stuff work on wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
  };
}
