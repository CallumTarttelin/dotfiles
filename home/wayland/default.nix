{pkgs, ...}: {
  imports = [
    ./hyprland.nix
    ./hyprpaper.nix
    ./idle.nix
    # mako, waybar, wofi now wrapped packages in modules/wrapped/
  ];

  home.packages = with pkgs; [
    # screenshot
    grim
    slurp

    # utils
    wl-clipboard

    # blue light filter
    gammastep
  ];

  # make stuff work on wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
  };
}
