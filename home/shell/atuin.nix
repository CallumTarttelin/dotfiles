{installShellCompletion, ...}: {
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
    settings = {
      dialect = "uk";
      sync_address = "http://nixie.tail86813.ts.net:8888";
      sync_frequency = "0";
    };
  };
}
