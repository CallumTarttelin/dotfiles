{
  lib,
  pkgs,
  ...
}: let
  dconf = "${pkgs.dconf}/bin/dconf";

  dconfDark = lib.hm.dag.entryAfter ["dconfSettings"] ''
    ${dconf} write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
  '';
in {
  imports = [
    ./neovim.nix
    ./foot.nix
  ];

  programs = {
    chromium = {
      enable = true;
    };

    firefox = {
      enable = true;
    };
  };

  services.syncthing.enable = true;

  # set dark as default theme
  home.activation = {inherit dconfDark;};
}
