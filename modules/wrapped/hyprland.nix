# Wrapped hyprland shared config.
# Monitor config and desktop shell (waybar/mako/wofi vs noctalia) are
# handled by the hyprland-desktop feature module, not baked in here.
_: {
  perSystem = {
    pkgs,
    self',
    lib,
    ...
  }: let
    lua = lib.generators.toLua {};
    q = builtins.toJSON;

    call = name: value: "hl.${name}(${lua value})";
    exec = cmd: "hl.exec_cmd(${q cmd})";
    execDsp = cmd: "hl.dsp.exec_cmd(${q cmd})";
    bind = key: dispatcher: "hl.bind(${q key}, ${dispatcher})";
    bindWith = key: dispatcher: opts: "hl.bind(${q key}, ${dispatcher}, ${lua opts})";

    sharedConfig = call "config" {
      misc.disable_splash_rendering = true;
      cursor.no_hardware_cursors = true;
      input = {
        kb_layout = "gb";
        follow_mouse = 1;
        touchpad.natural_scroll = false;
        sensitivity = 0;
      };
      general = {
        gaps_in = 0;
        gaps_out = 0;
        border_size = 0;
        col = {
          active_border = {
            colors = ["rgba(00000000)"];
            angle = 0;
          };
          inactive_border = "rgba(00000000)";
        };
        layout = "dwindle";
      };
      decoration = {
        rounding = 0;
        shadow = {
          enabled = false;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
        blur = {
          enabled = true;
          size = 3;
          passes = 1;
        };
      };
      dwindle.preserve_split = true;
    };

    curve = name: value: "hl.curve(${q name}, ${lua value})";
    animation = value: call "animation" value;

    focusBinds = let
      directions = {
        left = "l";
        right = "r";
        up = "u";
        down = "d";
        H = "l";
        J = "d";
        K = "u";
        L = "r";
      };
    in
      lib.mapAttrsToList (
        key: direction:
          bind "SUPER + ${key}" "hl.dsp.focus(${lua {inherit direction;}})"
      )
      directions;

    moveBinds = let
      directions = {
        left = "l";
        right = "r";
        up = "u";
        down = "d";
        H = "l";
        J = "d";
        K = "u";
        L = "r";
      };
    in
      lib.mapAttrsToList (
        key: direction:
          bind "SUPER + SHIFT + ${key}" "hl.dsp.window.move(${lua {inherit direction;}})"
      )
      directions;

    workspaceBinds = lib.flatten (map (workspace: let
        key = toString (lib.mod workspace 10);
      in [
        (bind "SUPER + ${key}" "hl.dsp.focus(${lua {inherit workspace;}})")
        (bind "SUPER + SHIFT + ${key}" "hl.dsp.window.move(${lua {inherit workspace;}})")
      ])
      (lib.range 1 10));

    startupCommands = [
      "wmname LG3D"
      "systemctl --user start hyprpolkitagent"
      "systemctl --user restart xdg-desktop-portal-gtk.service"
      "systemctl --user restart xdg-desktop-portal-hyprland.service"
    ];

    hyprlandLua = pkgs.writeText "hyprland-shared.lua" ''
      ${sharedConfig}

      hl.env("XCURSOR_SIZE", "24")

      ${curve "myBezier" {
        type = "bezier";
        points = [
          [0.05 0.9]
          [0.1 1.05]
        ];
      }}

      ${animation {
        leaf = "windows";
        enabled = true;
        speed = 3;
        bezier = "myBezier";
      }}
      ${animation {
        leaf = "windowsOut";
        enabled = true;
        speed = 3;
        bezier = "default";
        style = "popin 80%";
      }}
      ${animation {
        leaf = "border";
        enabled = false;
        speed = 5;
        bezier = "default";
      }}
      ${animation {
        leaf = "borderangle";
        enabled = false;
        speed = 3;
        bezier = "default";
      }}
      ${animation {
        leaf = "fade";
        enabled = true;
        speed = 3;
        bezier = "default";
      }}
      ${animation {
        leaf = "workspaces";
        enabled = true;
        speed = 2;
        bezier = "default";
      }}

      ${bind "SUPER + SHIFT + Q" "hl.dsp.window.close()"}
      ${bind "SUPER + RETURN" (execDsp (lib.getExe self'.packages.myGhostty))}
      ${bind "SUPER + M" "hl.dsp.exit()"}
      ${bind "SUPER + V" "hl.dsp.window.float(${lua {action = "toggle";}})"}
      ${bind "SUPER + F" "hl.dsp.window.fullscreen(${lua {
        mode = "fullscreen";
        action = "toggle";
      }})"}
      ${bind "SUPER + E" (execDsp "firefox")}
      ${bind "CTRL + SUPER + E" (execDsp (lib.getExe self'.packages.firefox-work))}
      ${bind "SUPER + SHIFT + E" (execDsp "firefox -private-window")}
      ${bind "PRINT" (execDsp "${pkgs.grimblast}/bin/grimblast copysave area")}

      ${lib.concatStringsSep "\n" focusBinds}

      ${lib.concatStringsSep "\n" moveBinds}

      ${lib.concatStringsSep "\n" workspaceBinds}

      ${bind "SUPER + O" "hl.dsp.workspace.move(${lua {monitor = "+1";}})"}
      ${bind "SUPER + P" "hl.dsp.workspace.move(${lua {monitor = "-1";}})"}

      ${bind "SUPER + mouse_down" "hl.dsp.focus(${lua {workspace = "e+1";}})"}
      ${bind "SUPER + mouse_up" "hl.dsp.focus(${lua {workspace = "e-1";}})"}

      ${bind "SUPER + SHIFT + S" (execDsp "scratchpad")}
      ${bind "SUPER + S" (execDsp "scratchpad -g")}

      ${bindWith "XF86AudioPlay" (execDsp "${pkgs.playerctl}/bin/playerctl play-pause") {locked = true;}}
      ${bindWith "XF86AudioNext" (execDsp "${pkgs.playerctl}/bin/playerctl next") {locked = true;}}
      ${bindWith "XF86AudioPrev" (execDsp "${pkgs.playerctl}/bin/playerctl previous") {locked = true;}}
      ${bindWith "XF86AudioRaiseVolume" (execDsp "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+") {
        locked = true;
        repeating = true;
      }}
      ${bindWith "XF86AudioLowerVolume" (execDsp "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") {
        locked = true;
        repeating = true;
      }}
      ${bindWith "XF86AudioMute" (execDsp "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") {locked = true;}}

      ${bindWith "SUPER + mouse:272" "hl.dsp.window.drag()" {mouse = true;}}
      ${bindWith "SUPER + mouse:273" "hl.dsp.window.resize()" {mouse = true;}}

      hl.on("hyprland.start", function()
      ${lib.concatMapStringsSep "\n" (cmd: "  ${exec cmd}") startupCommands}
      end)
    '';
  in {
    packages.myHyprlandLua = hyprlandLua;
    packages.myHyprlandConf = hyprlandLua;
  };
}
