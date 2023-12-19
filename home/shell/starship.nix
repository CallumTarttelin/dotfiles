{config, ...}: {
  home.sessionVariables.STARSHIP_CACHE = "${config.xdg.cacheHome}/starship";

  programs.starship = {
    enable = true;
    settings = {
      character = {
        success_symbol = "[π](green)";
        error_symbol = "[π](red)";
      };

      aws.disabled = true;
      gcloud.disabled = true;

      python.symbol = " ";
      rust.symbol = " ";
      nodejs.symbol = " ";
    };
  };
}
