{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.myGhostty = pkgs.symlinkJoin {
      name = "myGhostty";
      paths = [pkgs.ghostty];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/ghostty \
          --add-flags "--background=000000" \
          --add-flags "--background-opacity=0.6" \
          --add-flags "--theme='Monokai Remastered'" \
          --add-flags "--window-decoration=false" \
          --add-flags "--confirm-close-surface=false"
      '';
      meta.mainProgram = "ghostty";
    };
  };

  flake.nixosModules.ghostty = {config, lib, pkgs, ...}: {
    options.wrapped.ghostty.enable = lib.mkEnableOption "ghostty terminal";
    config = lib.mkIf config.wrapped.ghostty.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.myGhostty
      ];
    };
  };
}
