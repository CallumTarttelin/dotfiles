{pkgs, ...}: {

  programs.feh = {
    enable = true;
  };

  programs.mpv = {
    enable = true;
    config = {
      hwdec = "auto-safe";
      vo = "gpu";
      profile = "gpu-hq";
      gpu-context = "wayland";
      save-position-on-quit = true;
    };
  };

  home.packages = with pkgs; [
    spotify
  ];

}
