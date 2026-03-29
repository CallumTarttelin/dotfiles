_: {
  flake.nixosModules.k3s = {
    config,
    pkgs,
    lib,
    ...
  }: let
    cfg = config.features.k3s;

    k3sConfig = {
      disable = ["traefik" "servicelb" "flannel"];
      cluster-cidr = "10.42.0.0/16";
      service-cidr = "10.43.0.0/16";
      flannel-backend = "none";
    };

    k3sFlags =
      lib.concatStringsSep " " (
        lib.mapAttrsToList (
          k: v:
            if builtins.isList v
            then lib.concatMapStringsSep " " (x: "--${k}=${x}") v
            else "--${k}=${v}"
        )
        k3sConfig
      )
      + " --disable-network-policy";

    ciliumVersion = "1.17.4";
    ciliumHelm = pkgs.fetchurl {
      url = "https://helm.cilium.io/cilium-${ciliumVersion}.tgz";
      sha256 = "sha256-Btzt/iXAjHcNGTaQ1WEDcVPiM/nN4x4HBaBoAtJM6oc=";
    };
  in {
    options.features.k3s.enable = lib.mkEnableOption "K3s with Cilium and Flux";

    config = lib.mkIf cfg.enable {
      services.k3s = {
        enable = true;
        role = "server";
        extraFlags = k3sFlags;

        autoDeployCharts = {
          cilium = {
            enable = true;
            package = ciliumHelm;
            targetNamespace = "kube-system";
            values = {
              kubeProxyReplacement = "strict";
              routingMode = "native";
              bpf.masquerade = true;
              ipam.mode = "cluster-pool";
              bandwidthManager.enabled = true;
              bandwidthManager.bbr = true;
              policyEnforcementMode = "always";
              encryption = {
                enabled = true;
                type = "wireguard";
              };
              hubble = {
                relay.enabled = true;
                ui.enabled = true;
                metrics.enabled = [
                  "dns"
                  "drop"
                  "tcp"
                  "flow"
                  "port-distribution"
                  "icmp"
                  "http"
                ];
              };
              gatewayAPI.enabled = true;
              gatewayAPI.service = {
                enabled = true;
                type = "LoadBalancer";
                ports = [
                  {
                    name = "http";
                    port = 8080;
                  }
                  {
                    name = "https";
                    port = 8443;
                  }
                ];
              };
              agent.resources = {
                requests = {
                  cpu = "500m";
                  memory = "512Mi";
                };
                limits = {
                  cpu = "4";
                  memory = "4Gi";
                };
              };
              operator.resources = {
                requests = {
                  cpu = "250m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "2";
                  memory = "2Gi";
                };
              };
            };
          };
        };

        manifests = {
          flux-namespace = {
            enable = true;
            content = {
              apiVersion = "v1";
              kind = "Namespace";
              metadata.name = "flux-system";
            };
          };
          flux-bootstrap = {
            enable = true;
            target = "flux-bootstrap.yaml";
            content = {
              apiVersion = "v1";
              kind = "ConfigMap";
              metadata = {
                name = "flux-bootstrap-script";
                namespace = "flux-system";
              };
              data."bootstrap-command.txt" = ''
                flux bootstrap git \
                  --url=https://git.callumtarttelin.com/tarttelin/nixie-flux.git \
                  --branch=main \
                  --path=./clusters/personal \
                  --components-extra=image-reflector-controller,image-automation-controller \
                  --network-policy=false
              '';
            };
          };
        };
      };

      systemd.services.k3s-init = {
        partOf = ["k3s.service"];
        after = ["k3s.service"];
        serviceConfig.Type = "oneshot";
        script = ''
          until ${pkgs.kubectl}/bin/kubectl get nodes; do
            echo "Waiting for Kubernetes API..."
            sleep 2
          done
          ${pkgs.kubectl}/bin/kubectl create namespace monitoring --dry-run=client -o yaml | ${pkgs.kubectl}/bin/kubectl apply -f -
          ${pkgs.kubectl}/bin/kubectl create secret generic lgtm-credentials \
            --namespace=monitoring \
            --from-file=MINIO_PASSWORD=${config.age.secrets.k8s-minio.path} \
            --dry-run=client -o yaml | ${pkgs.kubectl}/bin/kubectl apply -f -
          ${pkgs.kubectl}/bin/kubectl create secret generic grafana-admin-credentials \
            --namespace=monitoring \
            --from-file=GF_SECURITY_ADMIN_PASSWORD=${config.age.secrets.k8s-grafana.path} \
            --dry-run=client -o yaml | ${pkgs.kubectl}/bin/kubectl apply -f -
        '';
      };

      environment.systemPackages = with pkgs; [
        kubectl
        kubernetes-helm
        cilium-cli
        hubble
        k9s
        stern
        kubectx
        fluxcd
        kn
        yq-go
      ];

      networking.firewall.allowedTCPPorts = [
        8080 # HTTP
        8443 # HTTPS
      ];
    };
  };
}
