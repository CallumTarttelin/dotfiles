{
  pkgs,
  lib,
  ...
}: let
  suspendScript = pkgs.writeShellScript "suspend-script" ''
    ${pkgs.pipewire}/bin/pw-cli i all | ${pkgs.ripgrep}/bin/rg running
    # only suspend if audio isn't running
    if [ $? == 1 ]; then
      ${pkgs.systemd}/bin/systemctl suspend
    fi
  '';
in {
  # screen idle
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 600;
          on-timeout = suspendScript.outPath;
        }
      ];
    };
  };

  systemd.user.services.hypridle.Install.WantedBy = lib.mkForce ["hyprland-session.target"];

  programs.hyprlock = {
    enable = true;
    settings = {
      background = {
        color = "#000000";
      };
      general = {
        ignore_empty_input = true;
      };
    };
  };
}
