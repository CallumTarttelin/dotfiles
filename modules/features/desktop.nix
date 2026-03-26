{...}: {
  flake.nixosModules.desktop = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.features.desktop.enable = lib.mkEnableOption "Desktop environment (fonts, audio, graphics)";

    config = lib.mkIf config.features.desktop.enable {
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

      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };
      services.pulseaudio.enable = lib.mkForce false;

      xdg.portal = {
        enable = true;
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
          xdg-desktop-portal-hyprland
        ];
        config.common.default = ["gtk" "hyprland"];
      };

      hardware = {
        graphics = {
          enable = true;
          enable32Bit = true;
          extraPackages = with pkgs; [
            libva
            libva-vdpau-driver
            libvdpau-va-gl
          ];
          extraPackages32 = with pkgs.pkgsi686Linux; [
            libva-vdpau-driver
            libvdpau-va-gl
          ];
        };
      };

      programs = {
        dconf.enable = true;
        kdeconnect.enable = true;
        seahorse.enable = true;
        xwayland.enable = true;
      };
      security.pam.services.swaylock.text = "auth include login";
      services.gnome.gnome-keyring.enable = true;

      environment.variables.NIXOS_OZONE_WL = "1";
    };
  };
}
