_: {
  home = {
    username = "tarttelin";
    homeDirectory = "/home/tarttelin";
    stateVersion = "23.11";
    extraOutputsToInstall = ["doc" "devdoc"];
  };

  manual = {
    html.enable = false;
    json.enable = false;
    manpages.enable = false;
  };

  programs.home-manager.enable = true;
}
