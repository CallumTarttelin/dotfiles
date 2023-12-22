{config, ...}: let
  browser = ["firefox"];
  # XDG MIME types
  associations = builtins.mapAttrs (_: v: (map (e: "${e}.desktop") v)) {
    "x-scheme-handler/http" = browser;
    "x-scheme-handler/https" = browser;
    "x-scheme-handler/ftp" = browser;
    "x-scheme-handler/chrome" = ["chromium-browser"];
    "text/html" = browser;
    "application/x-extension-htm" = browser;
    "application/x-extension-html" = browser;
    "application/x-extension-shtml" = browser;
    "application/x-extension-xhtml+xml" = browser;
    "application/x-extension-xht" = browser;
    "application/x-extension-xhtml" = browser;
    "x-scheme-handler/about" = browser;
    "x-scheme-handler/unknown" = browser;

    "audio/*" = ["mpv"];
    "video/*" = ["mpv"];
    "image/*" = ["feh"];
    "application/json" = browser;
    "application/pdf" = browser;
    "x-scheme-handler/discord" = ["discord"];
    "x-scheme-handler/spotify" = ["spotify"];
  };
in {
  xdg = {
    enable = true;
    mimeApps = {
      enable = true;
      defaultApplications = associations;
    };
    userDirs = {
      enable = true;
      createDirectories = true;
    };
  };
}
