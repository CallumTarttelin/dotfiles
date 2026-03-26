{
  imports = [
    ../../wayland
    ../../programs
    # HM modules that still need HM (programs.java, programs.go, programs.gradle)
    ../../programs/languages.nix
    # HM modules with config (programs.mpv, programs.feh, programs.zathura)
    ../../programs/media.nix
  ];

  # Bundled packages are now nixosModules loaded via modules/bundles/
  # Old HM imports removed: jetbrains, keepass, communication, drawing,
  # electronics, work, llms, office
}
