{self, ...}: {
  perSystem = {pkgs, lib, ...}: let
    spotifyScript = pkgs.writeShellScript "spotify-script" ''
      class=$(${pkgs.playerctl}/bin/playerctl metadata --player=spotify --format '{{lc(status)}}')
      icon=""

      if [[ $class == "playing" ]]; then
        info=$(${pkgs.playerctl}/bin/playerctl metadata --player=spotify --format '{{artist}} - {{title}}')
        if [[ ''${#info} > 40 ]]; then
          info=$(echo $info | cut -c1-40)"..."
        fi
        text=$info" "$icon
      elif [[ $class == "paused" ]]; then
        text=$icon
      elif [[ $class == "stopped" ]]; then
        text=""
      fi

      echo -e "{\"text\":\""$text"\", \"class\":\""$class"\"}"
    '';

    waybarConf = (pkgs.formats.json {}).generate "waybar-config" [
      {
        layer = "top";
        height = 30;
        spacing = 4;
        modules-left = ["hyprland/workspaces"];
        modules-center = ["hyprland/window"];
        modules-right = ["idle_inhibitor" "custom/spotify" "pulseaudio" "network" "cpu" "memory" "clock" "tray"];

        "hyprland/workspaces"."format-icons" = {
          active = "";
          default = "";
        };

        idle_inhibitor = {
          format = "{icon}";
          "format-icons" = {
            activated = "";
            deactivated = "";
          };
        };

        tray.spacing = 10;

        clock = {
          "tooltip-format" = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          "format-alt" = "{:%Y-%m-%d}";
        };

        cpu = {
          format = "{usage}% ";
          tooltip = false;
        };

        memory.format = "{}% ";

        pulseaudio = {
          format = "{volume}% {icon} {format_source}";
          "format-bluetooth" = "{volume}% {icon} {format_source}";
          "format-bluetooth-muted" = " {icon} {format_source}";
          "format-muted" = " {format_source}";
          "format-source" = "{volume}% ";
          "format-source-muted" = "";
          "format-icons" = {
            headphone = "";
            "hands-free" = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = ["" "" ""];
          };
          "on-click" = "${pkgs.pavucontrol}/bin/pavucontrol";
        };

        "custom/spotify" = {
          interval = 5;
          "return-type" = "json";
          exec = "${spotifyScript}";
          "exec-if" = "${pkgs.procps}/bin/pgrep spotify";
          escape = true;
          tooltip = false;
        };
      }
    ];

    waybarStyle = pkgs.writeText "waybar-style.css" ''
      * {
          border: none;
          border-radius: 0;
          font-family: Roboto, Helvetica, Arial, sans-serif;
          font-size: 13px;
          min-height: 0;
      }

      window#waybar {
          background-color: rgba(43, 48, 59, 1);
          color: #ffffff;
          transition-property: background-color;
          transition-duration: .5s;
          opacity: 1;
      }

      window#waybar.hidden {
          opacity: 0.2;
      }

      #workspaces button {
          padding: 0 5px;
          background-color: transparent;
          color: #ffffff;
          border-bottom: 3px solid transparent;
      }

      #workspaces button:hover {
          background: rgba(0, 0, 0, 0.2);
          border-bottom: 3px solid #ffffff;
      }

      #workspaces button.focused {
          background-color: #64727D;
          border-bottom: 3px solid #ffffff;
      }

      #workspaces button.urgent {
          background-color: #eb4d4b;
      }

      #clock,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #tray,
      #idle_inhibitor,
      #custom-spotify {
          padding: 0 10px;
          margin: 0 4px;
          color: #ffffff;
      }

      #clock { background-color: #64727D; }
      #cpu { background-color: #2ecc71; color: #000000; }
      #memory { background-color: #9b59b6; }
      #network { background-color: #2980b9; }
      #network.disconnected { background-color: #f53c3c; }
      #pulseaudio { background-color: #f1c40f; color: #000000; }
      #pulseaudio.muted { background-color: #90b1b1; color: #2a5c45; }
      #tray { background-color: #2980b9; }
      #idle_inhibitor { background-color: #2d3436; }
      #idle_inhibitor.activated { background-color: #ecf0f1; color: #2d3436; }
      #custom-spotify { background-color: #1DB954; color: #000000 }
    '';

    waybarConfigDir = pkgs.runCommand "waybar-config-dir" {} ''
      mkdir -p $out/waybar
      cp ${waybarConf} $out/waybar/config
      cp ${waybarStyle} $out/waybar/style.css
    '';
  in {
    packages.myWaybar = pkgs.symlinkJoin {
      name = "myWaybar";
      paths = [pkgs.waybar];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/waybar \
          --add-flags "--config ${waybarConfigDir}/waybar/config" \
          --add-flags "--style ${waybarConfigDir}/waybar/style.css" \
          --prefix PATH : ${lib.makeBinPath [pkgs.playerctl pkgs.procps pkgs.pavucontrol]}
      '';
      meta.mainProgram = "waybar";
    };
  };

  flake.nixosModules.waybar = {config, lib, pkgs, ...}: {
    options.wrapped.waybar.enable = lib.mkEnableOption "waybar status bar";
    config = lib.mkIf config.wrapped.waybar.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.myWaybar
        pkgs.playerctl
        pkgs.procps
        pkgs.pavucontrol
      ];
    };
  };
}
