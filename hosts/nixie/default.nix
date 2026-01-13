{
  pkgs,
  inputs,
  config,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking.hostName = "nixie";

  environment.systemPackages = with pkgs; [
    inputs.agenix.packages.x86_64-linux.default

    xdg-utils

    # Use the 'withComponents' package generator to define a Rust toolchain
    (inputs.fenix.packages.x86_64-linux.complete.withComponents [
      "cargo"
      "clippy"
      "rust-src"
      "rustc"
      "rustfmt"
    ])
    gcc
    gnumake
    protobuf
    protobufc
    nss
  ];

  networking.firewall.allowedTCPPorts = [80 443];

  security.acme = {
    acceptTerms = true;
    defaults.email = "acme@callumtarttelin.com";
    certs."callumtarttelin.com" = {
      group = config.services.caddy.group;
      domain = "callumtarttelin.com";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      dnsPropagationCheck = true;
      extraDomainNames = [
        "*.callumtarttelin.com"
      ];
      reloadServices = ["caddy"];
      environmentFile = config.age.secrets.cloudflare.path;
    };
  };

  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https off
    '';
    virtualHosts = {
      "hello.callumtarttelin.com".extraConfig = ''
        tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
          protocols tls1.3
        }
        respond "OK"
      '';
      "git.callumtarttelin.com".extraConfig = ''
        tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
          protocols tls1.3
        }
        reverse_proxy http://localhost:3000
      '';
      "sync.callumtarttelin.com".extraConfig = ''
        tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
          protocols tls1.3
        }
        reverse_proxy http://localhost:8384
      '';
      "vault.callumtarttelin.com".extraConfig = ''
        tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
          protocols tls1.3
        }
        reverse_proxy http://localhost:8812
      '';
    };
  };

  services.forgejo = {
    enable = true;
    database.type = "postgres";
    lfs.enable = true;
    settings.server = {
      SSH_PORT = 2222;
      PROTOCOL = "http"; # https terminates at reverse proxy
      ROOT_URL = "https://git.callumtarttelin.com";
    };
  };

  services.gitea-actions-runner = {
    instances.default = {
      enable = true;
      name = "default";
      url = "https://git.callumtarttelin.com";
      tokenFile = config.age.secrets.forgejo-runner.path;
      labels = [
        "nixos:docker://nixos/nix:latest"
        "ubuntu-latest:docker://ubuntu:latest"
        "debian-stable:docker://debian:stable"
        "alpine-latest:docker://alpine:latest"

        "python313:docker://python:3.13-bullseye"
        "node24:docker://node:24"
        "node24-alpine:docker://node:24-alpine"
        "go124://golang:1.24.4-bookworm"
        "rust://rust:1-bookworm"
        "java21://eclipse-temurin:21"
        "java24://eclipse-temurin:21"
        "gradle://gradle:8-noble"
      ];
    };
  };

  services.vaultwarden = {
    enable = true;
    environmentFile = config.age.secrets.yubi.path;
    config = {
      DOMAIN = "https://nixie/vault";
      SIGNUPS_ALLOWED = true;
      SIGNUPS_VERIFY = false;
      ROCKET_PORT = 8812;
    };
  };

  services.fwupd.enable = true;

  system.stateVersion = "24.05";
}
