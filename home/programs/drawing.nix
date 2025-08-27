{pkgs, ...}: {
  home.packages = with pkgs; [
    krita
    # audacity
    easyeffects
  ];
}
