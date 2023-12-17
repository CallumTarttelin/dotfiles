{
  pkgs,
  inputs,
  default,
  ...
}: {
  programs.regreet = {
    enable = true;
    cageArgs = ["-s" "-m" "last"];
  };

  security.pam.services.greetd.enableGnomeKeyring = true;
}
