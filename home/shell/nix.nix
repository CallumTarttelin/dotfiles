{
  pkgs,
  self,
  ...
}: let
  preUpdate = self.packages.${pkgs.stdenv.hostPlatform.system}.pre-update;
  updateT3code = self.packages.${pkgs.stdenv.hostPlatform.system}.update-t3code;
in {
  home.packages = with pkgs; [
    alejandra
    deadnix
    statix
    # comma and nix-index replaced by nix-index-database module
    preUpdate
    updateT3code
  ];

  programs.nix-index-database.comma.enable = true;

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config = {
      log_format = "-";
    };
  };
}
