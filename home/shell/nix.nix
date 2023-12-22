{pkgs, ...}: {
  home.packages = with pkgs; [
    alejandra
    deadnix
    statix
    comma
    nix-index
  ];

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
