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
    nss
    (writeShellScriptBin "backup-mount-s3" ''
      set -ea
      source ${config.age.secrets.restic-s3.path}
      mkdir -p /mnt/backup-s3
      exec ${restic}/bin/restic mount --allow-other /mnt/backup-s3
    '')
    (writeShellScriptBin "backup-mount-borgbase" ''
      set -ea
      source ${config.age.secrets.restic-borgbase.path}
      mkdir -p /mnt/backup-borgbase
      exec ${restic}/bin/restic mount --allow-other /mnt/backup-borgbase
    '')
  ];

  services.syncthing = {
    enable = true;
    user = "tarttelin";
    dataDir = "/home/tarttelin/sync";
    configDir = "/home/tarttelin/.config/syncthing";
    guiAddress = "0.0.0.0:8384";
  };

  networking.firewall.allowedTCPPorts = [80 443];

  security.acme = {
    acceptTerms = true;
    defaults.email = "acme@callumtarttelin.com";
    certs."callumtarttelin.com" = {
      inherit (config.services.caddy) group;
      domain = "callumtarttelin.com";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      dnsPropagationCheck = true;
      extraDomainNames = [
        "callumtarttelin.com"
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
      "nix-cache.callumtarttelin.com".extraConfig = ''
        tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
          protocols tls1.3
        }
        reverse_proxy http://localhost:5000
      '';
    };
  };

  services.forgejo = {
    enable = true;
    database.type = "postgres";
    lfs.enable = true;
    settings.server = {
      START_SSH_SERVER = true;
      SSH_DOMAIN = "git.callumtarttelin.com";
      SSH_PORT = 2222;
      SSH_LISTEN_PORT = 2222;
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
      settings.runner.capacity = 8;
      labels = [
        "nixos:docker://nixos/nix:latest"
        "ubuntu-latest:docker://ubuntu:latest"
        "debian-stable:docker://debian:stable"
        "alpine-latest:docker://alpine:latest"

        "python:docker://python:3"
        "node24:docker://node:24"
        "node24-alpine:docker://node:24-alpine"
        "go:docker://golang:1"
        "rust:docker://rust:1"
        "java25:docker://eclipse-temurin:25"
        "gradle:docker://gradle:jdk25"
      ];
    };
    # Native runner scoped to tarttelin/dotfiles in Forgejo UI
    # Register token at: git.callumtarttelin.com/tarttelin/dotfiles/settings/actions/runners
    instances.nix-native = {
      enable = true;
      name = "nix-native";
      url = "https://git.callumtarttelin.com";
      tokenFile = config.age.secrets.forgejo-runner-native.path;
      labels = ["nix-native:host"];
      hostPackages = with pkgs; [bash coreutils curl gawk git gnused gnutar gzip jq nix nodejs wget];
    };
  };

  services.vaultwarden = {
    enable = true;
    environmentFile = config.age.secrets.vaultwarden.path;
    config = {
      DOMAIN = "https://vault.callumtarttelin.com";
      SIGNUPS_ALLOWED = true;
      SIGNUPS_VERIFY = true;
      ROCKET_PORT = 8812;
      WEBSOCKET_ENABLED = true;
    };
  };

  # Auto-apply latest main — CI pre-builds the closure so this is near-instant
  systemd.services.nixie-auto-update = {
    description = "Apply latest dotfiles from main";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake git+https://git.callumtarttelin.com/tarttelin/dotfiles#nixie";
    };
    path = [pkgs.git pkgs.nix];
  };
  systemd.timers.nixie-auto-update = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 06:00:00"; # 6am daily, after CI builds at 3am
      Persistent = true;
    };
  };

  services.restic.backups = let
    nixiePaths = [
      "/var/backup/nixie"
      "/var/backup/restic"
    ];
  in {
    nixie-s3 = {
      environmentFile = config.age.secrets.restic-s3.path;
      paths = nixiePaths;
      backupPrepareCommand = ''
        ${pkgs.coreutils}/bin/mkdir -p /var/backup/nixie/vaultwarden
        ${pkgs.sqlite}/bin/sqlite3 /var/lib/bitwarden_rs/db.sqlite3 ".backup '/var/backup/nixie/vaultwarden/db.sqlite3'"
        ${pkgs.coreutils}/bin/cp -a /var/lib/bitwarden_rs/attachments /var/backup/nixie/vaultwarden/ 2>/dev/null || true
        ${pkgs.coreutils}/bin/cp -a /var/lib/bitwarden_rs/sends /var/backup/nixie/vaultwarden/ 2>/dev/null || true
        ${pkgs.coreutils}/bin/cp -a /var/lib/bitwarden_rs/rsa_key* /var/backup/nixie/vaultwarden/ 2>/dev/null || true
        ${pkgs.sudo}/bin/sudo -u postgres ${config.services.postgresql.package}/bin/pg_dump forgejo > /var/backup/nixie/forgejo.sql
        ${pkgs.coreutils}/bin/cp -a /var/lib/forgejo/repositories /var/backup/nixie/forgejo-repos 2>/dev/null || true
        ${pkgs.coreutils}/bin/cp -a /var/lib/forgejo/lfs /var/backup/nixie/forgejo-lfs 2>/dev/null || true
      '';
      extraBackupArgs = ["--compression max"];
      timerConfig = {
        OnCalendar = "*-*-* 01:00:00"; # daily, 1 hour after midnight client backup
        Persistent = true;
      };
      initialize = true;
    };
    nixie-borgbase = {
      environmentFile = config.age.secrets.restic-borgbase.path;
      paths = nixiePaths;
      extraBackupArgs = ["--compression max"];
      timerConfig = {
        OnCalendar = "*-*-* 01:00:00"; # daily, 1 hour after midnight client backup
        Persistent = true;
      };
      initialize = true;
    };
  };

  # BorgBase backup runs after S3 backup completes (shares the same staged data)
  systemd.services.restic-backups-nixie-borgbase = {
    after = ["restic-backups-nixie-s3.service"];
    requires = ["restic-backups-nixie-s3.service"];
  };

  services.fwupd.enable = true;

  system.stateVersion = "24.05";
}
