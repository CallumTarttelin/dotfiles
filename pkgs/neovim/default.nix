{
  pkgs,
  nixvim,
}: let
  nixvim' = nixvim.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
  nixvim'.makeNixvimWithModule {
    inherit pkgs;
    module = import ./config;
  }
