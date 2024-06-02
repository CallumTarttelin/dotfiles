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

      cmd_duration = {
        min_time = 500;
        format = "Took [$duration](bold yellow)";
      };
    };
  };
}
