{
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    jetbrains.idea-ultimate
    jetbrains.rust-rover
    jetbrains.webstorm
    jetbrains.pycharm-professional
  ];
}
