{self, ...}: {
  flake.nixosModules.hyprland-desktop = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.features.hyprland-desktop;
    selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
    hyprlandLua = selfpkgs.myHyprlandLua;
    noctalia = config.home-manager.users.tarttelin.programs.noctalia.package;
    lua = lib.generators.toLua {};
    q = builtins.toJSON;
    call = name: value: "hl.${name}(${lua value})";
    exec = cmd: "hl.exec_cmd(${q cmd})";
    execDsp = cmd: "hl.dsp.exec_cmd(${q cmd})";
    bind = key: dispatcher: "hl.bind(${q key}, ${dispatcher})";
    bindWith = key: dispatcher: opts: "hl.bind(${q key}, ${dispatcher}, ${lua opts})";
    dpmsCmd = action: "${pkgs.hyprland}/bin/hyprctl eval 'hl.dispatch(hl.dsp.dpms({ action = \"${action}\" }))'";
    lockCmd =
      if isNoctalia
      then "${ipc} session lock"
      else "${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null || ${pkgs.hyprlock}/bin/hyprlock";

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

    ipc = "${lib.getExe noctalia} msg";

    shellBinds =
      if isNoctalia
      then [
        (bind "SUPER + D" (execDsp "${ipc} panel-toggle launcher"))
        (bind "SUPER + C" (execDsp "${ipc} panel-toggle control-center"))
        (bind "SUPER + comma" (execDsp "${ipc} settings-toggle"))
        (bindWith "XF86MonBrightnessUp" (execDsp "${ipc} brightness-up") {
          locked = true;
          repeating = true;
        })
        (bindWith "XF86MonBrightnessDown" (execDsp "${ipc} brightness-down") {
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

    # Keep configuration as text so evaluation does not need to build it first.
    hostLua = ''
      ${hyprlandLua.text}

      ${lib.concatMapStringsSep "\n" monitorLua cfg.monitors}

      ${lib.concatStringsSep "\n" shellBinds}
      ${bind "CTRL + ALT + L" (execDsp lockCmd)}

      hl.on("hyprland.start", function()
      ${lib.concatMapStringsSep "\n" (e: "  ${exec e}") cfg.extraExecOnce}
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
      extraExecOnce = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
      idleLockTimeoutSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Seconds of inactivity before locking, or null to disable inactivity locking";
      };
    };

    config = lib.mkIf cfg.enable {
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
      security.pam.services.hyprlock = lib.mkIf isStandard {};
      security.pam.services.greetd.enableGnomeKeyring = true;
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
          enable = true;
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
          extraConfig = hostLua;
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

        # Noctalia owns idle, locking, and display power for its sessions.
        services.hypridle = lib.mkIf isStandard {
          enable = true;
          settings = {
            general = {
              lock_cmd = lib.mkDefault lockCmd;
              before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
              after_sleep_cmd = dpmsCmd "enable";
              on_unlock_cmd = dpmsCmd "enable";
              inhibit_sleep = 2;
            };
            listener =
              lib.optional (cfg.idleLockTimeoutSeconds != null) {
                timeout = cfg.idleLockTimeoutSeconds;
                on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
              }
              ++ [
                {
                  timeout = 660;
                  on-timeout = dpmsCmd "disable";
                  on-resume = dpmsCmd "enable";
                }
                {
                  timeout = 1800;
                  on-timeout = suspendScript.outPath;
                }
              ];
          };
        };

        programs.hyprlock = lib.mkIf isStandard {
          enable = true;
          settings = {
            background.color = "#000000";
            general = {
              disable_loading_bar = true;
              hide_cursor = true;
              ignore_empty_input = true;
            };
          };
        };

        home.packages =
          (lib.optionals isStandard (standardPackages ++ (with pkgs; [hyprsunset hyprshot grim slurp gammastep])))
          ++ (with pkgs; [
            grimblast
            satty
            wezterm
            wmname
            hyprpolkitagent
            wl-clipboard
          ]);
      };
    };
  };
}
