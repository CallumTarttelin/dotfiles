{pkgs, ...}: {
  home.packages = with pkgs; [
    discord
    slack
  ];

  #services.easyeffects.enable = true;
}
