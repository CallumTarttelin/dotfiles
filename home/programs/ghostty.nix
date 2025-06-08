{
  inputs,
  pkgs,
  ...
}: {
  home.packages = [
    pkgs.ghostty
  ];

  xdg.configFile."ghostty/config".text = ''
    background = 000000
    background-opacity = 0.6

    theme = Monokai Remastered
    window-decoration = false

    #    foreground = "FCFCFA";
    #    ## Normal/regular colors (color palette 0-7)
    #    regular0 = "403E41"; # black
    #    regular1 = "FF6188"; # red
    #    regular2 = "A9DC76"; # green
    #    regular3 = "FFD866"; # yellow
    #    regular4 = "FC9867"; # blue
    #    regular5 = "AB9DF2"; # magenta
    #    regular6 = "78DCE8"; # cyan
    #    regular7 = "FCFCFA"; # white
  '';
}
