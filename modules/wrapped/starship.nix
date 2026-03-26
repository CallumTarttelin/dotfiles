{self, ...}: {
  perSystem = {pkgs, ...}: let
    starshipConf = (pkgs.formats.toml {}).generate "starship.toml" {
      character = {
        success_symbol = "[π](green)";
        error_symbol = "[π](red)";
      };
      aws.disabled = true;
      gcloud.disabled = true;
      cmd_duration = {
        min_time = 500;
        format = "Took [$duration](bold yellow)";
      };
    };
  in {
    packages.myStarship = pkgs.symlinkJoin {
      name = "myStarship";
      paths = [pkgs.starship];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/starship \
          --set STARSHIP_CONFIG "${starshipConf}"
      '';
    };
  };

  flake.nixosModules.starship = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.myStarship
    ];
  };
}
