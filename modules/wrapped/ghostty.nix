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
          --add-flags "--window-decoration=false"
      '';
    };
  };

  flake.nixosModules.ghostty = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.myGhostty
    ];
  };
}
