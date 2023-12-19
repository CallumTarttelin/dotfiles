_: {
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    flags = ["--disable-up-arrow"];
    settings = {
      dialect = "uk";
      sync_address = "http://127.0.0.1:8888";
      sync_frequency = "0";
    };
  };
}
