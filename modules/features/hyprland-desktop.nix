{self, inputs, ...}: {
  flake.nixosModules.hyprland-desktop = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.features.hyprland-desktop;
    selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
    hyprlandConf = selfpkgs.myHyprlandConf;

    suspendScript = pkgs.writeShellScript "suspend-script" ''
      ${pkgs.pipewire}/bin/pw-cli i all | ${pkgs.ripgrep}/bin/rg running
      if [ $? == 1 ]; then
        ${pkgs.systemd}/bin/systemctl suspend
      fi
    '';

    isStandard = cfg.desktopShell == "standard";
    isNoctalia = cfg.desktopShell == "noctalia";

    standardPackages = [selfpkgs.myWaybar selfpkgs.myMako selfpkgs.myWofi];

    noctaliaExecOnce = []; # noctalia managed via systemd user service for restart-on-rebuild

    ipc = "${lib.getExe selfpkgs.myNoctalia} ipc call";

    shellBinds =
      if isNoctalia
      then ''
        bind = $mainMod, D, exec, ${ipc} launcher toggle
        bind = $mainMod, C, exec, ${ipc} controlCenter toggle
        bind = $mainMod, comma, exec, ${ipc} settings toggle
        bindel = , XF86MonBrightnessUp, exec, ${ipc} brightness increase
        bindel = , XF86MonBrightnessDown, exec, ${ipc} brightness decrease
      ''
      else ''
        bind = $mainMod, D, exec, ${lib.getExe selfpkgs.myWofi} --show drun
      '';

    hostConf = pkgs.writeText "hyprland-host.conf" ''
      source = ${hyprlandConf}

      ${lib.concatMapStringsSep "\n" (m: "monitor=${m}") cfg.monitors}

      ${shellBinds}

      ${lib.concatMapStringsSep "\n" (e: "exec-once = ${e}") (noctaliaExecOnce ++ cfg.extraExecOnce)}
    '';
  in {
    options.features.hyprland-desktop = {
      enable = lib.mkEnableOption "Hyprland desktop environment";
      monitors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [",preferred,auto,1"];
      };
      cursor = {
        package = lib.mkOption { type = lib.types.package; default = pkgs.bibata-cursors; };
        name = lib.mkOption { type = lib.types.str; default = "Bibata-Modern-Classic"; };
        size = lib.mkOption { type = lib.types.int; default = 16; };
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
    };

    config = lib.mkIf cfg.enable {
      # System-level
      programs.hyprland = { enable = true; withUWSM = true; };
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
          material-symbols noto-fonts noto-fonts-cjk-sans noto-fonts-color-emoji
          roboto (google-fonts.override {fonts = ["Inter"];})
          nerd-fonts.fira-code nerd-fonts.jetbrains-mono
        ];
        enableDefaultPackages = false;
        fontconfig.defaultFonts = {
          serif = ["Noto Serif" "Noto Color Emoji"];
          sansSerif = ["Inter" "Noto Color Emoji"];
          monospace = ["JetBrainsMono Nerd Font" "Noto Color Emoji"];
          emoji = ["Noto Color Emoji"];
        };
      };

      services.pipewire = { enable = true; alsa.enable = true; alsa.support32Bit = true; pulse.enable = true; };
      services.pulseaudio.enable = lib.mkForce false;
      hardware.graphics = {
        enable = true; enable32Bit = true;
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
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd start-hyprland";
          user = "greeter";
        };
      };

      # Home-manager config
      home-manager.users.tarttelin = {
        home.pointerCursor = {
          gtk.enable = true;
          package = cfg.cursor.package;
          name = cfg.cursor.name;
          size = cfg.cursor.size;
        };

        wayland.windowManager.hyprland = {
          enable = true;
          systemd = { variables = ["--all"]; enable = true; };
          extraConfig = builtins.readFile hostConf;
        };

        home.sessionVariables = {
          QT_QPA_PLATFORM = "wayland";
          SDL_VIDEODRIVER = "wayland";
          XDG_SESSION_TYPE = "wayland";
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
            ExecStart = "${lib.getExe selfpkgs.myNoctalia}";
            Restart = "on-failure";
            RestartSec = 1;
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

        # Hypridle + Hyprlock (shared across both shells)
        services.hypridle = {
          enable = true;
          settings = {
            general = {
              lock_cmd = lib.mkDefault "pidof hyprlock || hyprlock";
              before_sleep_cmd = "loginctl lock-session";
              after_sleep_cmd = "hyprctl dispatch dpms on";
            };
            listener = [
              {timeout = 600; on-timeout = suspendScript.outPath;}
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
          (lib.optionals isStandard standardPackages)
          ++ (lib.optionals isNoctalia [selfpkgs.myNoctalia])
          ++ (with pkgs; [
            grimblast wezterm wmname hyprsunset hyprshot hyprpolkitagent
            grim slurp wl-clipboard gammastep
          ]);
      };
    };
  };
}
