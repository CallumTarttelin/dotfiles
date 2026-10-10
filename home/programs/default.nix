{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./wezterm.nix
  ];

  programs = {
    chromium = {
      enable = true;
    };

    firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
    };
  };

  home.packages = [
    pkgs.obsidian
    pkgs.bruno
    pkgs.postman
    pkgs.websocat
    pkgs.google-chrome
  ];
}
