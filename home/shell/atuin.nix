{installShellCompletion, ...}: {
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
    settings = {
      dialect = "uk";
      sync_address = "http://nixie.oryx-harmonic.ts.net:8888";
      sync_frequency = "0";
      enter_accept = true;
      style = "full";
      inline_height = 0;
    };
  };
}
