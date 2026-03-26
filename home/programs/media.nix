# HM programs with config that aren't wrapped/bundled yet.
# feh, spotify, pulsemixer, qpwgraph are in modules/bundles/media.nix
{...}: {
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
}
