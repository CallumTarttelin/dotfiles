{
  config,
  pkgs,
  lib,
  ...
}: let
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
  nfsVersion = "4.0.18";
  nfsHelm = pkgs.fetchurl {
    url = "https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/releases/download/nfs-subdir-external-provisioner-4.0.18/nfs-subdir-external-provisioner-4.0.18.tgz";
    sha256 = "";
  };
in {
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

          agent = {
            resources = {
              requests = {
                cpu = "500m";
                memory = "512Mi";
              };
              limits = {
                cpu = "4";
                memory = "4Gi";
              };
            };
          };
          operator = {
            resources = {
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
    };

    # Deploy Flux bootstrap manifests
    manifests = {
      flux-namespace = {
        enable = true;
        content = {
          apiVersion = "v1";
          kind = "Namespace";
          metadata = {
            name = "flux-system";
          };
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
          data = {
            "bootstrap-command.txt" = ''
              #
              # FluxCD Bootstrap Instructions
              #
              # Run the following command from a machine with kubectl configured for this cluster
              # and the Flux CLI installed.
              #
              # Replace YOUR_GIT_USER, YOUR_GIT_REPO, and YOUR_GIT_BRANCH, YOUR_CLUSTER_PATH as appropriate.
              # Example: ssh://git@github.com/your-user/your-flux-repo.git
              # Example path: ./clusters/my-k3s-cluster
              #
              flux bootstrap git \
                --url=https://git.callumtarttelin.com/tarttelin/nixie-flux.git \
                --branch=main \
                --path=./clusters/personal \
                --components-extra=image-reflector-controller,image-automation-controller \
                --network-policy=false # Set to true if you have network policies for flux-system

              #
              # Ensure your Git repository contains:
              # 1. HelmRepository resources for chart sources.
              # 2. HelmRelease resources for each application, specifying chart versions and values.
              # 3. Kustomization resources to organize your deployments.
              # 4. Secrets (e.g., for MinIO, Grafana) managed securely (e.g., using SOPS).
              #
            '';
          };
        };
      };
    };
  };

  systemd.services.k3s-init = {
    partOf = ["k3s.service"];
    after = ["k3s.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      # Wait for the Kubernetes API to be ready
      # This is a simple readiness check
      until ${pkgs.kubectl}/bin/kubectl get nodes; do
        echo "Waiting for Kubernetes API..."
        sleep 2
      done

      # Create the monitoring namespace if it doesn't exist
      ${pkgs.kubectl}/bin/kubectl create namespace monitoring --dry-run=client -o yaml | ${pkgs.kubectl}/bin/kubectl apply -f -

      # Create a generic secret for MinIO/Loki credentials
      ${pkgs.kubectl}/bin/kubectl create secret generic lgtm-credentials \
        --namespace=monitoring \
        --from-file=MINIO_PASSWORD=${config.age.secrets.k8s-minio.path} \
        --dry-run=client -o yaml | ${pkgs.kubectl}/bin/kubectl apply -f -

      # Create a separate secret for the Grafana admin password
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

  networking.firewall = {
    allowedTCPPorts = [
      # 6443  # k3s API
      8080 # Traefik HTTP
      8443 # Traefik HTTPS
      # 9000  # gRPC
    ];
    # allowedUDPPorts = [ 8472 ];  # Cilium VXLAN
  };
}
