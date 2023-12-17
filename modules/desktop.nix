{
  pkgs,
  lib,
  ...
}: {
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-hyprland
    ];
    config.common.default = ["gtk" "hyprland"];
  };

  hardware = {
    opengl = {
      extraPackages = with pkgs; [
        libva
        vaapiVdpau
        libvdpau-va-gl
      ];
      extraPackages32 = with pkgs.pkgsi686Linux; [
        vaapiVdpau
        libvdpau-va-gl
      ];
    };
    pulseaudio.enable = lib.mkForce false;
  };

  programs = {
    dconf.enable = true;
    kdeconnect.enable = true;
    seahorse.enable = true;
  };
  security = {
    pam.services.swaylock.text = "auth include login";
  };
  services.gnome.gnome-keyring.enable = true;

  environment.variables.NIXOS_OZONE_WL = "1";
}
