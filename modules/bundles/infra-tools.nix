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
        google-cloud-sdk
      ];
    };
  };

  flake.nixosModules.infra-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.bundles.infra-tools.enable = lib.mkEnableOption "infrastructure tools (kubectl, helm, k9s, aws)";
    config = lib.mkIf config.bundles.infra-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.infra-tools
        self.packages.${pkgs.stdenv.hostPlatform.system}.gcloud-remote-login
      ];
    };
  };
}
