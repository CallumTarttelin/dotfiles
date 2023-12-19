_: {
  programs.regreet = {
    enable = true;
    cageArgs = ["-s"];
    settings = {
      GTK = {
        application_prefer_dark_theme = true;
        theme_name = "Adwaita";
      };
      commands = {
        reboot = ["systemctl" "reboot"];
        poweroff = ["systemctl" "poweroff"];
      };
    };
  };

  security.pam.services.greetd.enableGnomeKeyring = true;
}
