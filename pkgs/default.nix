{
  pkgs,
  flake,
  nixvim,
}: let
  updateT3code = pkgs.callPackage ./update-t3code {inherit flake;};
  nvim = import ./neovim {inherit pkgs nixvim;};
in {
  inherit nvim;
  myNeovim = nvim;

  t3code = pkgs.callPackage ./t3code {};
  update-t3code = updateT3code;
  pre-update = pkgs.callPackage ./pre-update {
    inherit updateT3code;
  };
}
