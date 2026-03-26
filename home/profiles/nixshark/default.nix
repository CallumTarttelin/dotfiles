{
  imports = [
    # wayland is now handled by features.hyprland-desktop
    ../../programs
    # languages.nix removed - env vars now owned by bundles (jvm-tools, go-tools)
    # HM modules with config (programs.mpv, programs.feh, programs.zathura)
    ../../programs/media.nix
  ];
}
