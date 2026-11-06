{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.kubernetes-tools = pkgs.buildEnv {
      name = "kubernetes-tools";
      paths = with pkgs; [
        kubectl
        kubernetes-helm
        k9s
        stern
        kubectx
        fluxcd
      ];
    };

    packages.infra-tools = pkgs.buildEnv {
      name = "infra-tools";
      paths = with pkgs; [
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
  }: let
    cfg = config.bundles.infra-tools;
  in {
    options.bundles.infra-tools = {
      enable = lib.mkEnableOption "infrastructure tools (aws, gcloud, yq)";
      kubernetes.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include Kubernetes tools in the infrastructure bundle.";
      };
    };
    config = lib.mkIf cfg.enable {
      home-manager.users.tarttelin.home.packages =
        [
          self.packages.${pkgs.stdenv.hostPlatform.system}.infra-tools
          self.packages.${pkgs.stdenv.hostPlatform.system}.gcloud-remote-login
        ]
        ++ lib.optional cfg.kubernetes.enable self.packages.${pkgs.stdenv.hostPlatform.system}.kubernetes-tools;
    };
  };
}
