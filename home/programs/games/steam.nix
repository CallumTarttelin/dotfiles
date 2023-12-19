{pkgs, ...}: {
  home.packages = with pkgs; [
    gamescope
    gamemode
    mangohud
    steam
  ];
}
