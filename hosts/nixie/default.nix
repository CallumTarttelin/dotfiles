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

  users.users.ninassin = {
    isNormalUser = true;
    description = "ninassin";
    home = "/home/ninassin";
    createHome = true;
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
    hashedPasswordFile = config.age.secrets.root.path;
  };

  environment.systemPackages = with pkgs; [
    inputs.agenix.packages.x86_64-linux.default
    xdg-utils
    nss
    intel-gpu-tools
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
      servers {
        metrics
      }
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
      "photos.callumtarttelin.com".extraConfig = ''
        tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
          protocols tls1.3
        }
        reverse_proxy http://127.0.0.1:2283
      '';
    };
  };

  services.immich = {
    enable = true;
    package = inputs."nixpkgs-master".legacyPackages.${pkgs.stdenv.hostPlatform.system}.immich;
    host = "127.0.0.1";
    port = 2283;
    mediaLocation = "/var/lib/immich";
    openFirewall = false;
    accelerationDevices = ["/dev/dri/renderD128"];

    database = {
      enable = true;
      createDB = true;
      host = "/run/postgresql";
      name = "immich";
      user = "immich";
    };

    machine-learning.enable = true;

    settings = {
      server.externalDomain = "https://photos.callumtarttelin.com";
      ffmpeg = {
        accel = "qsv";
        accelDecode = true;
      };
      notifications.smtp = {
        enabled = true;
        from = "photos@callumtarttelin.com";
        replyTo = "photos@callumtarttelin.com";
        transport = {
          ignoreCert = false;
          host._secret = config.age.secrets.ses-smtp-addr.path;
          port = 465;
          username._secret = config.age.secrets.ses-smtp-user.path;
          password._secret = config.age.secrets.ses-smtp-password.path;
        };
      };
    };
  };

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
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
    settings.mailer = {
      ENABLED = true;
      PROTOCOL = "smtps";
      FROM = "git@callumtarttelin.com";
    };
    secrets.mailer = {
      SMTP_ADDR = config.age.secrets.ses-smtp-addr.path;
      SMTP_PORT = config.age.secrets.ses-smtp-port.path;
      USER = config.age.secrets.ses-smtp-user.path;
      PASSWD = config.age.secrets.ses-smtp-password.path;
    };
    dump = {
      enable = true;
      backupDir = "/var/backup/nixie/forgejo-dump";
      type = "tar"; # no compression — restic handles it
      interval = "00:00:00"; # midnight, before 1am restic run
    };
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
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

      settings.cache = {
        enabled = true;
        dir = "/var/cache/forgejo-runner";
      };
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
    backupDir = "/var/backup/nixie/vaultwarden";
    config = {
      DOMAIN = "https://vault.callumtarttelin.com";
      SIGNUPS_ALLOWED = true;
      SIGNUPS_VERIFY = true;
      ROCKET_PORT = 8812;
      WEBSOCKET_ENABLED = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/backup/nixie/immich-dump 0750 postgres postgres - -"
  ];

  systemd.services.backup-immich = {
    description = "Backup Immich database";
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
    path = [config.services.postgresql.package pkgs.coreutils];
    script = ''
      set -euo pipefail
      cd /var/backup/nixie/immich-dump
      pg_dump --clean --if-exists --dbname=immich --file=immich-database.sql.tmp
      mv immich-database.sql.tmp immich-database.sql
      chmod 0640 immich-database.sql
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      WorkingDirectory = "/var/backup/nixie/immich-dump";
    };
  };

  systemd.timers.backup-immich = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "00:00:00";
      Persistent = true;
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
      "/var/lib/immich"
    ];
  in {
    nixie-s3 = {
      environmentFile = config.age.secrets.restic-s3.path;
      paths = nixiePaths;
      # Vaultwarden backup: /var/backup/nixie/vaultwarden (runs at midnight)
      # Forgejo backup: /var/backup/nixie/forgejo-dump (runs at midnight)
      # Immich DB dump: /var/backup/nixie/immich-dump (runs at midnight)
      # Immich media/library: /var/lib/immich
      # Service-specific backups land before this 1am restic run
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

  # Override default 23:00 to midnight, consistent with forgejo dump
  systemd.timers.backup-vaultwarden.timerConfig.OnCalendar = "00:00:00";

  services.fwupd.enable = true;

  system.stateVersion = "24.05";
}
