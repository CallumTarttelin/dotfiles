{
  flake.nixosModules.noctalia = {
    config,
    lib,
    pkgs,
    ...
  }: let
    desktop = config.features.hyprland-desktop;
    isLaptop = config.networking.hostName == "nixwork";
    noctalia = config.home-manager.users.tarttelin.programs.noctalia.package;
    idleSuspend = pkgs.writeShellScript "noctalia-idle-suspend" ''
      # Spotify may let the displays sleep, but any running audio prevents suspend.
      ${pkgs.pipewire}/bin/pw-cli i all | ${pkgs.ripgrep}/bin/rg running
      if [ $? == 1 ]; then
        exec ${lib.getExe noctalia} msg session lock-and-suspend
      fi
    '';
    sessionAction = action: shortcut: {
      inherit action shortcut;
      countdown_seconds = 10;
    };
  in {
    config = lib.mkIf desktop.enable {
      xdg.sounds.enable = true;

      home-manager.users.tarttelin = {
        programs.noctalia = {
          enable = true;
          systemd.enable = true;
          settings = {
            shell = {
              lang = "en-GB";
              avatar_path = "/home/tarttelin/Downloads/Saskcow_Icon_Blue__Orange.png";
              telemetry_enabled = false;
              setup_wizard_enabled = false;
              launch_apps_as_systemd_services = true;
              clipboard_auto_paste = "off";
              panel = {
                launcher_placement = "floating";
                launcher_position = "center";
                control_center_placement = "attached";
                transparency_mode = "soft";
              };
              launcher = {
                app_grid = false;
                categories = false;
                sort_by_usage = true;
              };
              session.actions = [
                (sessionAction "lock" "1")
                (sessionAction "lock_and_suspend" "2")
                {
                  action = "command";
                  label = "Hibernate";
                  glyph = "bed";
                  command = "${pkgs.systemd}/bin/systemctl hibernate";
                  shortcut = "3";
                  countdown_seconds = 10;
                }
                (sessionAction "reboot" "4")
                (sessionAction "logout" "5")
                (sessionAction "shutdown" "6")
                {
                  action = "command";
                  label = "Reboot to firmware";
                  glyph = "settings";
                  command = "${pkgs.systemd}/bin/systemctl reboot --firmware-setup";
                  shortcut = "7";
                  countdown_seconds = 10;
                }
              ];
            };

            theme = {
              mode = "dark";
              shell_mode = "dark";
              source = "builtin";
              builtin = "Ayu";
            };

            bar.default = {
              position = "top";
              background_opacity = 0.93;
              margin_edge = 0;
              margin_ends = 0;
              radius_top_left = 0;
              radius_top_right = 0;
              padding = 2;
              widget_spacing = 6;
              capsule = true;
              start =
                ["launcher" "clock"]
                ++ lib.optional isLaptop "battery"
                ++ ["cpu" "cpu-temp" "ram" "privacy" "active_window"];
              center = ["workspaces"];
              end = ["media" "tray" "notifications" "network" "nightlight" "caffeine" "control-center"];
            };

            widget = {
              clock = {
                format = "{:%H:%M %a, %b %d}";
                vertical_format = "{:%H %M - %d %m}";
                tooltip_format = "{:%H:%M %a, %b %d}";
              };
              cpu = {
                type = "sysmon";
                stat = "cpu_usage";
                visualization = "none";
              };
              cpu-temp = {
                type = "sysmon";
                stat = "cpu_temp";
                visualization = "none";
              };
              ram = {
                type = "sysmon";
                stat = "ram_used";
                visualization = "none";
              };
              privacy.hide_inactive = true;
              active_window = {
                max_length = 145;
                title_scroll = "on_hover";
              };
              workspaces = {
                max_label_chars = 2;
                labels_only_when_occupied = true;
                focused_color = "primary";
                occupied_color = "secondary";
                empty_color = "secondary";
              };
              media = {
                artist_first = true;
                max_length = 145;
                title_scroll = "on_hover";
                hide_when_no_media = true;
              };
              tray = {
                drawer = true;
                hide_passive = false;
                pinned = ["Discord" "spotify-client"];
              };
              battery.display_mode = "graphic";
            };

            control_center.shortcuts = map (type: {inherit type;}) (
              ["wifi" "bluetooth" "wallpaper"]
              ++ lib.optional isLaptop "power_profile"
              ++ lib.optional (!isLaptop) "notification"
              ++ ["caffeine" "nightlight"]
            );

            wallpaper = {
              enabled = true;
              directory = "/home/tarttelin/Pictures/Wallpapers";
              default.path = "/home/tarttelin/Pictures/Wallpapers/s-p-a-c-e-2-2560x1440.jpg";
              fill_mode = "crop";
            };
            location = {
              auto_locate = false;
              address = "Reading, UK";
            };
            weather = {
              enabled = true;
              unit = "metric";
            };
            nightlight = {
              enabled = true;
              temperature_day = 6500;
              temperature_night = 4000;
            };

            notification = {
              position = "top_right";
              layer = "overlay";
              keep_dismissed_in_history = false;
            };
            osd.position = "top_right";
            dock.enabled = false;
            desktop_widgets.enabled = false;
            plugins = {
              enabled = [];
              auto_update = "none";
            };

            lockscreen = {
              enabled = true;
              lock_before_suspend = true;
            };
            lockscreen_widgets.enabled = false;
            idle = {
              pre_action_fade_seconds = 0;
              behavior_order = ["lock" "screen-off" "suspend"];
              behavior = {
                lock = {
                  enabled = desktop.idleLockTimeoutSeconds != null;
                  timeout =
                    if desktop.idleLockTimeoutSeconds == null
                    then 0
                    else desktop.idleLockTimeoutSeconds;
                  action = "lock";
                };
                screen-off = {
                  enabled = true;
                  timeout = 660;
                  action = "screen_off";
                };
                suspend = {
                  enabled = true;
                  timeout = 1800;
                  action = "command";
                  command = toString idleSuspend;
                };
              };
            };
          };
        };

        # Preserve the per-user PATH previously supplied by the custom shell service.
        systemd.user.services.noctalia.Service.Environment = [
          "PATH=/etc/profiles/per-user/tarttelin/bin:/run/current-system/sw/bin:/run/wrappers/bin"
        ];
      };
    };
  };
}
