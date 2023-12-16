{
  inputs,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    grimblast
  ];

  # enable hyprland
  wayland.windowManager.hyprland = {
    enable = true;
    extraConfig = ''
      #
      # Please note not all available settings / options are set here.
      # For a full list, see the wiki
      #


      # See https://wiki.hyprland.org/Configuring/Monitors/
      monitor=DP-1,preferred,1920x0,1
      monitor=DP-2,preferred,0x0,1
      monitor=HDMI-A-1,preferred,4480x0,1
      monitor=,preferred,auto,1


      # See https://wiki.hyprland.org/Configuring/Keywords/ for more

      # Execute your favorite apps at launch
      exec-once = hyprpaper
      exec-once = waybar
      exec-once = wmname LG3D
      exec-once = mako
      exec-once = /usr/bin/gnome-keyring-daemon --start --components=ssh,secrets
      exec-once = foot --server

      # Not quite sure what this does, but apparently it's good to do
      exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
      exec-once = systemctl --user restart xdg-desktop-portal.service
      exec-once = systemctl --user restart xdg-desktop-portal-gtk.service
      exec-once = systemctl --user restart xdg-desktop-portal-hyprland.service

      # Source a file (multi-file configs)
      # source = ~/.config/hypr/myColors.conf

      # Some default env vars.
      env = XCURSOR_SIZE,24

      # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
      input {
          kb_layout = gb
          kb_variant =
          kb_model =
          kb_options =
          kb_rules =

          follow_mouse = 1

          touchpad {
              natural_scroll = no
          }

          sensitivity = 0 # -1.0 - 1.0, 0 means no modification.
      }

      general {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more

          gaps_in = 0 # 2
          gaps_out = 0 # 2

          border_size = 0 # 1
          col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
          col.inactive_border = rgba(595959aa)

          layout = dwindle
      }

      decoration {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more
          rounding = 1
          drop_shadow = yes
          shadow_range = 4
          shadow_render_power = 3
          col.shadow = rgba(1a1a1aee)

          blur {
              enabled = yes
              size = 3
              passes = 1
          }
      }

      animations {
          # enabled = false # TODO consider if I want these, maybe cool

          # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

          bezier = myBezier, 0.05, 0.9, 0.1, 1.05

          # animation = windows, 1, 7, myBezier
          # animation = windowsOut, 1, 7, default, popin 80%
          # animation = border, 1, 10, default
          # animation = borderangle, 1, 8, default
          # animation = fade, 1, 7, default
          # animation = workspaces, 1, 6, default

          animation = windows, 1, 3, myBezier
          animation = windowsOut, 1, 3, default, popin 80%
          animation = border, 1, 5, default
          animation = borderangle, 1, 3, default
          animation = fade, 1, 3, default
          animation = workspaces, 1, 2, default
      }

      dwindle {
          # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
          pseudotile = yes # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
          preserve_split = yes # you probably want this
      }

      master {
          # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
          new_is_master = true
      }

      gestures {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more
          workspace_swipe = off
      }

      # Example per-device config
      # See https://wiki.hyprland.org/Configuring/Keywords/#executing for more
      device:epic-mouse-v1 {
          sensitivity = -0.5
      }

      # Example windowrule v1
      # windowrule = float, ^(kitty)$
      # Example windowrule v2
      # windowrulev2 = float,class:^(kitty)$,title:^(kitty)$
      # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more


      # See https://wiki.hyprland.org/Configuring/Keywords/ for more
      $mainMod = SUPER
      $shiftMod = SUPER_SHIFT

      # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
      bind = $shiftMod, Q, killactive
      bind = $mainMod, RETURN, exec, foot
      bind = $mainMod, M, exit,
      # bind = $mainMod, E, exec, dolphin
      bind = $mainMod, V, togglefloating,
      bind = $mainMod, D, exec, wofi --show drun
      # bind = $mainMod, P, pseudo, # dwindle
      # bind = $mainMod, J, togglesplit, # dwindle
      bind = $mainMod, F, fullscreen,

      # Move focus with mainMod + arrow keys
      bind = $mainMod, left, movefocus, l
      bind = $mainMod, right, movefocus, r
      bind = $mainMod, up, movefocus, u
      bind = $mainMod, down, movefocus, d
      bind = $mainMod, h, movefocus, l
      bind = $mainMod, j, movefocus, d
      bind = $mainMod, k, movefocus, u
      bind = $mainMod, l, movefocus, r

      bind = $shiftMod, left, movewindow, l
      bind = $shiftMod, right, movewindow, r
      bind = $shiftMod, up, movewindow, u
      bind = $shiftMod, down, movewindow, d
      bind = $shiftMod, h, movewindow, l
      bind = $shiftMod, j, movewindow, d
      bind = $shiftMod, k, movewindow, u
      bind = $shiftMod, l, movewindow, r

      # Switch workspaces with mainMod + [0-9]
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

      # Move active window to a workspace with mainMod + SHIFT + [0-9]
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

      # Scroll through existing workspaces with mainMod + scroll
      bind = $mainMod, mouse_down, workspace, e+1
      bind = $mainMod, mouse_up, workspace, e-1

      # Scratchpad
      bind = $shiftMod, s, exec, scratchpad
      bind = $mainMod, s, exec, scratchpad -g

      # Mouse Passthrough
      # bind = ,mouse:276,pass,(Discord)
      # bind = ,mouse:275,pass,(Discord)

      # Move/resize windows with mainMod + LMB/RMB and dragging
      bindm = $mainMod, mouse:272, movewindow
      bindm = $mainMod, mouse:273, resizewindow

    '';
  };
}
