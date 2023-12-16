{
  pkgs,
  inputs,
  lib,
  default,
  ...
}: {
  xdg.configFile."hypr/hyprpaper.conf".text = ''
    preload = ~/.config/sway/backgrounds/s-p-a-c-e-2-2560×1440.jpg
    wallpaper = , ~/.config/sway/backgrounds/s-p-a-c-e-2-2560×1440.jpg
  '';

  systemd.user.services.hyprpaper = {
    Unit = {
      Description = "Hyprland wallpaper daemon";
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.hyprpaper}.default}";
      Restart = "on-failure";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
