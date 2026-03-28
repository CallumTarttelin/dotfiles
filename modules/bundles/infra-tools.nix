{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.infra-tools = pkgs.buildEnv {
      name = "infra-tools";
      paths = with pkgs; [
        kubectl
        kubernetes-helm
        k9s
        stern
        kubectx
        fluxcd
        yq-go
        awscli2
      ];
    };
  };

  flake.nixosModules.infra-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.infra-tools
    ];
  };
}
