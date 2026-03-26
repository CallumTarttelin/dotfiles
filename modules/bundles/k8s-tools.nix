{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.k8s-tools = pkgs.buildEnv {
      name = "k8s-tools";
      paths = with pkgs; [
        kubectl
        kubernetes-helm
        k9s
        stern
        kubectx
        fluxcd
        yq-go
      ];
    };
  };

  flake.nixosModules.k8s-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.k8s-tools
    ];
  };
}
