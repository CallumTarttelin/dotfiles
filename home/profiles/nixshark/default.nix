{
  imports = [
    # wayland is now handled by features.hyprland-desktop
    ../../programs
    # HM modules that still need HM (programs.java, programs.go, programs.gradle)
    ../../programs/languages.nix
    # HM modules with config (programs.mpv, programs.feh, programs.zathura)
    ../../programs/media.nix
  ];
}
