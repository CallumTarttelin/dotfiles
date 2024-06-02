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

  programs.zathura = {
    enable = true;
    options = {
      database = "sqlite";
    };
  };

  home.packages = with pkgs; [
    spotify
    pulsemixer
    qpwgraph
    helvum
  ];

}
