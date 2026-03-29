{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.social = pkgs.buildEnv {
      name = "social";
      paths = with pkgs; [discord slack];
    };
  };

  flake.nixosModules.social = {config, lib, pkgs, ...}: {
    options.bundles.social.enable = lib.mkEnableOption "social apps (discord, slack)";
    config = lib.mkIf config.bundles.social.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.social
      ];
    };
  };
}
