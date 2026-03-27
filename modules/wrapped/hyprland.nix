# Wrapped hyprland shared config.
# Monitor config and desktop shell (waybar/mako/wofi vs noctalia) are
# handled by the hyprland-desktop feature module, not baked in here.
{self, ...}: {
  perSystem = {
    pkgs,
    self',
    lib,
    ...
  }: let
    hyprlandConf = pkgs.writeText "hyprland-shared.conf" ''
      misc {
        disable_splash_rendering = true
      }

      env = XCURSOR_SIZE,24
      cursor {
        no_hardware_cursors = true
      }

      input {
        kb_layout = gb
        follow_mouse = 1
        touchpad {
          natural_scroll = no
        }
        sensitivity = 0
      }

      general {
        gaps_in = 0
        gaps_out = 0
        border_size = 0
        col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
        col.inactive_border = rgba(595959aa)
        layout = dwindle
      }

      decoration {
        rounding = 1
        shadow {
          enabled = true
          range = 4
          render_power = 3
          color = rgba(1a1a1aee)
        }
        blur {
          enabled = yes
          size = 3
          passes = 1
        }
      }

      animations {
        bezier = myBezier, 0.05, 0.9, 0.1, 1.05
        animation = windows, 1, 3, myBezier
        animation = windowsOut, 1, 3, default, popin 80%
        animation = border, 1, 5, default
        animation = borderangle, 1, 3, default
        animation = fade, 1, 3, default
        animation = workspaces, 1, 2, default
      }

      dwindle {
        pseudotile = yes
        preserve_split = yes
      }

      $mainMod = SUPER
      $shiftMod = SUPER_SHIFT

      bind = $shiftMod, Q, killactive
      bind = $mainMod, RETURN, exec, ${lib.getExe self'.packages.myGhostty}
      bind = $mainMod, M, exit,
      bind = $mainMod, V, togglefloating,
      # launcher bind set by hyprland-desktop feature (wofi or noctalia)
      bind = $mainMod, F, fullscreen,
      bind = $mainMod, E, exec, firefox
      bind = $shiftMod, E, exec, firefox -private-window
      bind = , PRINT, exec, ${pkgs.grimblast}/bin/grimblast copysave area

      # Focus
      bind = $mainMod, left, movefocus, l
      bind = $mainMod, right, movefocus, r
      bind = $mainMod, up, movefocus, u
      bind = $mainMod, down, movefocus, d
      bind = $mainMod, h, movefocus, l
      bind = $mainMod, j, movefocus, d
      bind = $mainMod, k, movefocus, u
      bind = $mainMod, l, movefocus, r

      # Move windows
      bind = $shiftMod, left, movewindow, l
      bind = $shiftMod, right, movewindow, r
      bind = $shiftMod, up, movewindow, u
      bind = $shiftMod, down, movewindow, d
      bind = $shiftMod, h, movewindow, l
      bind = $shiftMod, j, movewindow, d
      bind = $shiftMod, k, movewindow, u
      bind = $shiftMod, l, movewindow, r

      # Workspaces
      bind = $mainMod, 1, workspace, 1
      bind = $mainMod, 2, workspace, 2
      bind = $mainMod, 3, workspace, 3
      bind = $mainMod, 4, workspace, 4
      bind = $mainMod, 5, workspace, 5
      bind = $mainMod, 6, workspace, 6
      bind = $mainMod, 7, workspace, 7
      bind = $mainMod, 8, workspace, 8
      bind = $mainMod, 9, workspace, 9
      bind = $mainMod, 0, workspace, 10

      bind = $mainMod SHIFT, 1, movetoworkspace, 1
      bind = $mainMod SHIFT, 2, movetoworkspace, 2
      bind = $mainMod SHIFT, 3, movetoworkspace, 3
      bind = $mainMod SHIFT, 4, movetoworkspace, 4
      bind = $mainMod SHIFT, 5, movetoworkspace, 5
      bind = $mainMod SHIFT, 6, movetoworkspace, 6
      bind = $mainMod SHIFT, 7, movetoworkspace, 7
      bind = $mainMod SHIFT, 8, movetoworkspace, 8
      bind = $mainMod SHIFT, 9, movetoworkspace, 9
      bind = $mainMod SHIFT, 0, movetoworkspace, 10

      bind = $mainMod, O, movecurrentworkspacetomonitor, +1
      bind = $mainMod, P, movecurrentworkspacetomonitor, -1

      bind = $mainMod, mouse_down, workspace, e+1
      bind = $mainMod, mouse_up, workspace, e-1

      bind = $shiftMod, s, exec, scratchpad
      bind = $mainMod, s, exec, scratchpad -g

      # Media keys
      bindl = , XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause
      bindl = , XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next
      bindl = , XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous
      bindel = , XF86AudioRaiseVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
      bindel = , XF86AudioLowerVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
      bindl = , XF86AudioMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

      bindm = $mainMod, mouse:272, movewindow
      bindm = $mainMod, mouse:273, resizewindow

      # Core exec-once (portal/polkit restarts)
      exec-once = wmname LG3D
      exec-once = systemctl --user start hyprpolkitagent
      exec-once = systemctl --user restart xdg-desktop-portal-gtk.service
      exec-once = systemctl --user restart xdg-desktop-portal-hyprland.service
    '';
  in {
    packages.myHyprlandConf = hyprlandConf;
  };
}
