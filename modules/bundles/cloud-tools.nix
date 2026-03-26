{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.cloud-tools = pkgs.buildEnv {
      name = "cloud-tools";
      paths = with pkgs; [awscli2 deploy-rs];
    };
  };

  flake.nixosModules.cloud-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.cloud-tools
    ];
  };
}
