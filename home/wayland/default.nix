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
    wl-screenrec

    # blue light filter
    gammastep
  ];

  systemd.user.services.polkit-gnome = {
    Unit = {
      Description = "PolicyKit Authentication Agent";
      After = ["graphical-session-pre.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  # make stuff work on wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
  };
}
