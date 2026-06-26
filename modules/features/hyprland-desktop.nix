{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.hyprland-desktop = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.features.hyprland-desktop;
    selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
    hyprlandLua = selfpkgs.myHyprlandLua;
    myNoctalia = cfg.noctaliaPackage;
    lua = lib.generators.toLua {};
    q = builtins.toJSON;
    call = name: value: "hl.${name}(${lua value})";
    exec = cmd: "hl.exec_cmd(${q cmd})";
    execDsp = cmd: "hl.dsp.exec_cmd(${q cmd})";
    bind = key: dispatcher: "hl.bind(${q key}, ${dispatcher})";
    bindWith = key: dispatcher: opts: "hl.bind(${q key}, ${dispatcher}, ${lua opts})";

    suspendScript = pkgs.writeShellScript "suspend-script" ''
      ${pkgs.pipewire}/bin/pw-cli i all | ${pkgs.ripgrep}/bin/rg running
      if [ $? == 1 ]; then
        ${pkgs.systemd}/bin/systemctl suspend
      fi
    '';

    pipewireIdleInhibitConfig = pkgs.writeText "wayland-pipewire-idle-inhibit.toml" ''
      verbosity = "WARN"
      media_minimum_duration = 10
      idle_inhibitor = "wayland"
      sink_whitelist = []

      [[node_blacklist]]
      app_name = "[Ss]potify"
    '';

    hyprlandDpmsResumeScript = pkgs.writeShellScript "hyprland-dpms-on-resume" ''
      if [ "''${1:-}" != post ]; then
        exit 0
      fi

      ${pkgs.coreutils}/bin/sleep 1

      for runtime_dir in /run/user/[0-9]*; do
        [ -d "$runtime_dir/hypr" ] || continue

        uid="''${runtime_dir#/run/user/}"
        user="$(${pkgs.glibc.bin}/bin/getent passwd "$uid" | ${pkgs.coreutils}/bin/cut -d: -f1)"
        [ -n "$user" ] || continue

        for instance_dir in "$runtime_dir"/hypr/*; do
          [ -d "$instance_dir" ] || continue

          signature="''${instance_dir##*/}"
          ${pkgs.util-linux}/bin/runuser -u "$user" -- \
            ${pkgs.coreutils}/bin/env \
            XDG_RUNTIME_DIR="$runtime_dir" \
            HYPRLAND_INSTANCE_SIGNATURE="$signature" \
            ${pkgs.hyprland}/bin/hyprctl eval 'hl.dispatch(hl.dsp.dpms({ action = "on" }))' >/dev/null 2>&1 || true
        done
      done
    '';

    isStandard = cfg.desktopShell == "standard";
    isNoctalia = cfg.desktopShell == "noctalia";

    standardPackages = [selfpkgs.myWaybar selfpkgs.myMako selfpkgs.myWofi];

    startHyprland = pkgs.writeShellScript "start-hyprland-with-home-session" ''
      hmSessionVars="/etc/profiles/per-user/tarttelin/etc/profile.d/hm-session-vars.sh"
      if [ -r "$hmSessionVars" ]; then
        . "$hmSessionVars"
      fi

      exec /run/current-system/sw/bin/start-hyprland
    '';

    noctaliaExecOnce = []; # noctalia managed via systemd user service

    ipc = "${lib.getExe myNoctalia} ipc call";

    shellBinds =
      if isNoctalia
      then [
        (bind "SUPER + D" (execDsp "${ipc} launcher toggle"))
        (bind "SUPER + C" (execDsp "${ipc} controlCenter toggle"))
        (bind "SUPER + comma" (execDsp "${ipc} settings toggle"))
        (bindWith "XF86MonBrightnessUp" (execDsp "${ipc} brightness increase") {
          locked = true;
          repeating = true;
        })
        (bindWith "XF86MonBrightnessDown" (execDsp "${ipc} brightness decrease") {
          locked = true;
          repeating = true;
        })
      ]
      else [
        (bind "SUPER + D" (execDsp "${lib.getExe selfpkgs.myWofi} --show drun"))
      ];

    parseMonitorValue = value: let
      trimmed = lib.trim value;
    in
      if builtins.match "-?[0-9]+([.][0-9]+)?" trimmed != null
      then builtins.fromJSON trimmed
      else trimmed;

    parseMonitorExtras = fields:
      if fields == []
      then {}
      else let
        key = lib.trim (builtins.elemAt fields 0);
        value = parseMonitorValue (builtins.elemAt fields 1);
        rest = lib.drop 2 fields;
      in
        {${key} = value;} // parseMonitorExtras rest;

    monitorLua = monitor: let
      fields = map lib.trim (lib.splitString "," monitor);
      output = builtins.elemAt fields 0;
      mode = builtins.elemAt fields 1;
      position = builtins.elemAt fields 2;
      scale = parseMonitorValue (builtins.elemAt fields 3);
      extras = parseMonitorExtras (lib.drop 4 fields);
    in
      call "monitor" ({
          inherit output mode position scale;
        }
        // extras);

    hostLua = pkgs.writeText "hyprland-host.lua" ''
      ${builtins.readFile hyprlandLua}

      ${lib.concatMapStringsSep "\n" monitorLua cfg.monitors}

      ${lib.concatStringsSep "\n" shellBinds}

      hl.on("hyprland.start", function()
      ${lib.concatMapStringsSep "\n" (e: "  ${exec e}") (noctaliaExecOnce ++ cfg.extraExecOnce)}
      end)
    '';
  in {
    options.features.hyprland-desktop = {
      enable = lib.mkEnableOption "Hyprland desktop environment";
      monitors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [",preferred,auto,1"];
      };
      cursor = {
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.bibata-cursors;
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "Bibata-Modern-Classic";
        };
        size = lib.mkOption {
          type = lib.types.int;
          default = 16;
        };
      };
      desktopShell = lib.mkOption {
        type = lib.types.enum ["standard" "noctalia"];
        default = "standard";
        description = "Desktop shell: standard (waybar + mako + wofi) or noctalia (unified shell)";
      };
      noctaliaPackage = lib.mkOption {
        type = lib.types.package;
        inherit (inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}) default;
        description = "Noctalia package to use; defaults to upstream, override with per-host wrapped variant";
      };
      extraExecOnce = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
    };

    config = lib.mkIf cfg.enable {
      noctalia.enable = isNoctalia;

      # System-level
      programs.hyprland = {
        enable = true;
        withUWSM = true;
      };
      programs.uwsm = {
        enable = true;
        waylandCompositors.hyprland = {
          prettyName = "Hyprland";
          comment = "Hyprland compositor managed by UWSM";
          binPath = "/run/current-system/sw/bin/start-hyprland";
        };
      };
      security.pam.services.hyprlock = {};
      security.pam.services.greetd.enableGnomeKeyring = true;
      security.pam.services.swaylock.text = "auth include login";
      security.rtkit.enable = true;

      xdg.portal = {
        enable = true;
        extraPortals = with pkgs; [xdg-desktop-portal-hyprland xdg-desktop-portal-gtk];
        config.common.default = ["gtk" "hyprland"];
      };

      fonts = {
        packages = with pkgs; [
          material-symbols
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          roboto
          (google-fonts.override {fonts = ["Inter"];})
          nerd-fonts.fira-code
          nerd-fonts.jetbrains-mono
        ];
        enableDefaultPackages = false;
        fontconfig.defaultFonts = {
          serif = ["Noto Serif" "Noto Color Emoji"];
          sansSerif = ["Inter" "Noto Color Emoji"];
          monospace = ["JetBrainsMono Nerd Font" "Noto Color Emoji"];
          emoji = ["Noto Color Emoji"];
        };
      };

      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };
      services.pulseaudio.enable = lib.mkForce false;
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [libva libva-vdpau-driver libvdpau-va-gl];
        extraPackages32 = with pkgs.pkgsi686Linux; [libva-vdpau-driver libvdpau-va-gl];
      };

      programs.dconf.enable = true;
      programs.kdeconnect.enable = true;
      programs.seahorse.enable = true;
      programs.xwayland.enable = true;
      services.gnome.gnome-keyring.enable = true;
      environment.variables.NIXOS_OZONE_WL = "1";
      environment.etc."systemd/system-sleep/hyprland-dpms-on-resume".source = lib.mkIf isNoctalia hyprlandDpmsResumeScript;

      services.greetd = {
        enable = true;
        settings.default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${startHyprland}";
          user = "greeter";
        };
      };

      # Home-manager config
      home-manager.users.tarttelin = {
        home.pointerCursor = {
          gtk.enable = true;
          inherit (cfg.cursor) package;
          inherit (cfg.cursor) name;
          inherit (cfg.cursor) size;
        };

        wayland.windowManager.hyprland = {
          enable = true;
          configType = "lua";
          systemd = {
            variables = ["--all"];
            enable = true;
          };
          extraConfig = builtins.readFile hostLua;
        };

        home.sessionVariables = {
          QT_QPA_PLATFORM = "wayland";
          SDL_VIDEODRIVER = "wayland";
          XDG_SESSION_TYPE = "wayland";
          SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-agent";
        };

        # Wallpapers
        home.file."Pictures/Wallpapers/aperture-science-bg.jpg".source = ./_wallpapers/aperture-science-bg.jpg;
        home.file."Pictures/Wallpapers/s-p-a-c-e-2-1920x1080.jpg".source = ./_wallpapers/s-p-a-c-e-2-1920x1080.jpg;
        home.file."Pictures/Wallpapers/s-p-a-c-e-2-2560x1440.jpg".source = ./_wallpapers/s-p-a-c-e-2-2560x1440.jpg;

        # Standard shell: waybar + mako via systemd
        systemd.user.services.waybar = lib.mkIf isStandard {
          Unit = {
            Description = "Waybar status bar";
            PartOf = ["graphical-session.target"];
            After = ["graphical-session.target"];
          };
          Service = {
            ExecStart = "${lib.getExe selfpkgs.myWaybar}";
            Restart = "on-failure";
            RestartSec = 1;
          };
          Install.WantedBy = ["graphical-session.target"];
        };

        systemd.user.services.mako = lib.mkIf isStandard {
          Unit = {
            Description = "Mako notification daemon";
            PartOf = ["graphical-session.target"];
            After = ["graphical-session.target"];
          };
          Service = {
            ExecStart = "${lib.getExe selfpkgs.myMako}";
            Restart = "on-failure";
            RestartSec = 1;
          };
          Install.WantedBy = ["graphical-session.target"];
        };

        # Noctalia: systemd user service so it restarts on rebuild (store path change)
        systemd.user.services.noctalia-shell = lib.mkIf isNoctalia {
          Unit = {
            Description = "Noctalia desktop shell";
            PartOf = ["graphical-session.target"];
            After = ["graphical-session.target"];
          };
          Service = {
            ExecStart = "${lib.getExe myNoctalia}";
            Environment = [
              "PATH=/etc/profiles/per-user/tarttelin/bin:/run/current-system/sw/bin:/run/wrappers/bin"
            ];
            Restart = "on-failure";
            RestartSec = 1;
          };
          Install.WantedBy = ["graphical-session.target"];
        };

        systemd.user.services.wayland-pipewire-idle-inhibit = lib.mkIf isNoctalia {
          Unit = {
            Description = "Inhibit Wayland idle while media is playing";
            PartOf = ["graphical-session.target"];
            After = ["graphical-session.target" "pipewire.service"];
          };
          Service = {
            ExecStart = "${lib.getExe pkgs.wayland-pipewire-idle-inhibit} --config ${pipewireIdleInhibitConfig}";
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = ["graphical-session.target"];
        };

        # Hyprpaper - not needed with noctalia (has built-in wallpaper management)
        services.hyprpaper = lib.mkIf isStandard {
          enable = true;
          settings.wallpaper = {
            monitor = "";
            path = "~/Pictures/Wallpapers/s-p-a-c-e-2-2560x1440.jpg";
          };
        };

        # Hypridle + Hyprlock (standard shell only — noctalia has built-in idle management)
        services.hypridle = lib.mkIf isStandard {
          enable = true;
          settings = {
            general = {
              lock_cmd = lib.mkDefault "pidof hyprlock || hyprlock";
              before_sleep_cmd = "loginctl lock-session";
              after_sleep_cmd = "hyprctl eval 'hl.dispatch(hl.dsp.dpms({ action = \"on\" }))'";
            };
            listener = [
              {
                timeout = 600;
                on-timeout = suspendScript.outPath;
              }
            ];
          };
        };

        programs.hyprlock = lib.mkIf isStandard {
          enable = true;
          settings = {
            background.color = "#000000";
            general.ignore_empty_input = true;
          };
        };

        home.packages =
          (lib.optionals isStandard (standardPackages ++ [pkgs.hyprsunset]))
          ++ (lib.optionals isNoctalia ([myNoctalia]
            ++ (with pkgs; [
              brightnessctl
              imagemagick
              python3
              git
              cliphist
              wlsunset
              evolution-data-server
            ])))
          ++ (with pkgs; [
            grimblast
            wezterm
            wmname
            hyprshot
            hyprpolkitagent
            satty
            grim
            slurp
            wl-clipboard
            gammastep
          ]);
      };
    };
  };
}
