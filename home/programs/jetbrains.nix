{pkgs, ...}: {
  home.packages = with pkgs; [
    jetbrains.idea
    jetbrains.rust-rover
    jetbrains.clion
    zed-editor
  ];
}
