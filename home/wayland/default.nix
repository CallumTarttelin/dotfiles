{pkgs, ...}: {
  imports = [
    ./hyprland.nix
    ./hyprpaper.nix
    ./idle.nix
    ./mako.nix
    ./waybar.nix
    ./wofi.nix
  ];

  home.packages = with pkgs; [
    # screenshot
    grim
    slurp
    waybar

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
