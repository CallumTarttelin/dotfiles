{
  config,
  inputs,
  lib,
  pkgs,
  self,
  ...
}: let
  packages = self.packages.${pkgs.stdenv.hostPlatform.system};
  gateway = packages.inference-gateway;
  model = "deepseek/deepseek-v4.1-flash-1017";
  runtime = "/run/inference";
  state = "/var/lib/inference-gateway";
  openaiProfile = pkgs.writeText "hermes-openai-settings.json" (builtins.toJSON {
    model = {
      default = "gpt-6.1-sol";
      provider = "nixie-openai";
    };
    # Named custom providers preserve the Responses transport on loopback URLs.
    providers.nixie-openai = {
      base_url = "http://127.0.0.1:8090/openai/v1";
      key_env = "NIXIE_OPENAI_API_KEY";
      api_mode = "codex_responses";
    };
    skills = {
      disabled = ["google-workspace" "gws-gmail"];
      auto_load = [];
      external_dirs = [];
      project_discovery = false;
    };
    terminal = {
      backend = "local";
      timeout = 180;
    };
    auxiliary = lib.genAttrs ["vision" "web_extract" "compression" "title_generation" "session_search" "curator" "background_review"] (_: {
      provider = "main";
      model = "gpt-6.1-sol";
    });
    compression.provider = "main";
    fallback_providers = [];
  });
  profileSetup = pkgs.runCommand "hermes-openai-profile-setup" {} ''
    mkdir check
    cp ${./hermes-openai/setup.py} check/setup.py
    cp ${./hermes-openai/test_setup.py} check/test_setup.py
    cp ${./hermes-openai/SOUL.md} check/SOUL.md
    HOME=$TMPDIR ${config.services.hermes-agent.package.hermesVenv}/bin/python3 \
      check/test_setup.py --settings ${openaiProfile} -v
    install -Dm444 check/setup.py $out/lib/setup.py
  '';
  hermesGws = pkgs.writeShellScriptBin "gws" ''
    if [ "''${HERMES_HOME:-/var/lib/hermes/.hermes}" != /var/lib/hermes/.hermes ]; then
      echo "Google Workspace is private to the default Phala profile; start a chat there." >&2
      exit 1
    fi
    export GOOGLE_WORKSPACE_CLI_CONFIG_DIR=/var/lib/hermes/.config/gws
    export GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file
    exec ${pkgs.gws}/bin/gws "$@"
  '';
  lockedRestic = pkgs.writeShellScriptBin "restic" ''
    exec ${pkgs.util-linux}/bin/flock --shared ${state}/export.lock ${pkgs.restic}/bin/restic "$@"
  '';
  encryptedKey = ../../secrets/phala-api-key.age;
  hasEncryptedKey = builtins.pathExists encryptedKey;
  keyFile =
    if hasEncryptedKey
    then config.age.secrets.phala-api-key.path
    else "/var/lib/inference-credentials/phala-api-key";
  spec = pkgs.writeText "inference-provision.json" (builtins.toJSON {
    credentials_dir = "/var/lib/inference-credentials";
    runtime_dir = runtime;
    phala_key_file = keyFile;
    client_registry_file = "/var/lib/inference-client-keys/keys.json";
    operator = "tarttelin";
    inherit model;
  });
  hardened = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
    CapabilityBoundingSet = "";
    UMask = "0077";
    Restart = "on-failure";
    RestartSec = "5s";
  };
  provisionDependency = {
    after = ["inference-credentials.service"];
    requires = ["inference-credentials.service"];
  };
in {
  age.secrets =
    {hermes-dashboard.file = ../../secrets/hermes-dashboard.age;}
    // lib.optionalAttrs hasEncryptedKey {
      phala-api-key.file = encryptedKey;
    };

  users.groups.inference-gateway = {};
  users.users.inference-gateway = {
    isSystemUser = true;
    group = "inference-gateway";
    home = state;
  };
  users.groups.cliproxyapi = {};
  users.users.cliproxyapi = {
    isSystemUser = true;
    group = "cliproxyapi";
    home = "/var/lib/cliproxyapi";
  };
  users.groups.phala-verifier = {};
  users.users.phala-verifier = {
    isSystemUser = true;
    group = "phala-verifier";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/inference-credentials 0700 root root - -"
    "d /var/lib/inference-client-keys 0750 root inference-gateway - -"
    "d ${state} 0700 inference-gateway inference-gateway - -"
    "f ${state}/export.lock 0600 inference-gateway inference-gateway - -"
    "d /var/lib/cliproxyapi 0700 cliproxyapi cliproxyapi - -"
    "d /var/lib/cliproxyapi/auth 0700 cliproxyapi cliproxyapi - -"
    "d /var/lib/hermes/.config/gws 0700 hermes hermes - -"
  ];

  systemd.services.inference-credentials = {
    description = "Prepare private inference credentials outside the Nix store";
    wantedBy = ["multi-user.target"];
    after = ["agenix.service" "systemd-tmpfiles-setup.service"];
    before = ["inference-gateway.service" "cliproxyapi.service" "hermes-profiles.service" "hermes-agent.service" "hermes-backend.service"];
    restartTriggers = [spec] ++ lib.optional hasEncryptedKey encryptedKey;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
      ExecStartPre = "${pkgs.coreutils}/bin/test -s ${keyFile}";
      ExecStart = "${gateway}/bin/inference-provision ${spec}";
    };
  };

  systemd.services.cliproxyapi =
    provisionDependency
    // {
      description = "OpenAI subscription inference via CLIProxyAPI";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      serviceConfig =
        hardened
        // {
          User = "cliproxyapi";
          Group = "cliproxyapi";
          StateDirectory = "cliproxyapi";
          WorkingDirectory = "/var/lib/cliproxyapi";
          ExecStart = "${packages.cliproxyapi}/bin/cliproxyapi -config ${runtime}/cliproxyapi.yaml -local-model";
        };
      environment.HOME = "/var/lib/cliproxyapi";
    };

  systemd.services.phala-verifier = {
    description = "Phala attestation and streaming receipt verifier";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig =
      hardened
      // {
        User = "phala-verifier";
        Group = "phala-verifier";
        StateDirectory = "phala-verifier";
        ExecStart = lib.escapeShellArgs [
          "${packages.private-ai-proxy}/bin/pap"
          "serve"
          "https://inference.phala.com"
          "--listen"
          "127.0.0.1:4180"
          "--control"
          "127.0.0.1:4183"
          "--require-claim"
          "tee_attested"
          "--json-events"
        ];
      };
    environment.HOME = "/var/lib/phala-verifier";
  };

  systemd.services.inference-gateway =
    provisionDependency
    // {
      description = "Streaming inference gateway and durable event journal";
      wantedBy = ["multi-user.target"];
      wants = ["phala-verifier.service" "cliproxyapi.service"];
      restartTriggers = [spec] ++ lib.optional hasEncryptedKey encryptedKey;
      serviceConfig =
        hardened
        // {
          User = "inference-gateway";
          Group = "inference-gateway";
          StateDirectory = "inference-gateway";
          SyslogLevelPrefix = true;
          StateDirectoryMode = "0700";
          TimeoutStopSec = 150;
          ExecStart = "${gateway}/bin/inference-gateway --config ${runtime}/gateway.json --state-dir ${state} --port 8090";
        };
    };

  systemd.services.inference-archive = {
    description = "Compact completed inference journals into Zstd Parquet";
    serviceConfig =
      hardened
      // {
        Type = "oneshot";
        Restart = "no";
        User = "inference-gateway";
        Group = "inference-gateway";
        ReadWritePaths = [state];
        Nice = 15;
        IOSchedulingClass = "idle";
        ExecStart = "${gateway}/bin/inference-archive --state-dir ${state}";
      };
  };
  systemd.timers.inference-archive = {
    wantedBy = ["timers.target"];
    # Local Europe/London time; change this to match the meter's actual cheap window.
    timerConfig = {
      OnCalendar = "*-*-* 00:30:00";
      Persistent = false;
    };
  };

  services.hermes-agent = {
    enable = true;
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
    addToSystemPackages = false;
    extraPackages = [hermesGws];
    hermesHomeFiles."skills/gws-gmail/SKILL.md" = ./hermes-gmail/SKILL.md;
    backend = {
      mode = "dashboard";
      host = "127.0.0.1";
      port = 9119;
    };
    settings = {
      dashboard.public_url = "https://hermes.callumtarttelin.com";
      skills = {
        # The bundled Google skill requires ~/.hermes/google_token.json and
        # overrides gws's credential path. Use our directly authenticated CLI.
        disabled = ["google-workspace" "productivity/google-workspace"];
        auto_load = ["gws-gmail"];
      };
      model = {
        default = model;
        provider = "custom";
        base_url = "http://127.0.0.1:8090/phala/v1";
        key_env = "OPENAI_API_KEY";
        api_mode = "chat_completions";
      };
      terminal = {
        backend = "local";
        timeout = 180;
      };
      auxiliary = lib.genAttrs ["vision" "web_extract" "compression" "title_generation" "session_search" "curator" "background_review"] (_: {
        provider = "main";
        inherit model;
      });
      compression.provider = "main";
      fallback_providers = [];
    };
  };
  systemd.services.hermes-agent = {
    after = ["inference-credentials.service" "inference-gateway.service" "hermes-profiles.service"];
    requires = ["inference-credentials.service" "hermes-profiles.service"];
    preStart = lib.mkAfter ''
      install -m 0600 ${runtime}/hermes.env /var/lib/hermes/.hermes/.env
    '';
    serviceConfig.EnvironmentFile = "${runtime}/hermes.env";
  };
  systemd.services.hermes-profiles = {
    description = "Prepare the separate OpenAI Hermes profile";
    wantedBy = ["multi-user.target"];
    after = ["inference-credentials.service" "systemd-tmpfiles-setup.service"];
    requires = ["inference-credentials.service"];
    before = ["hermes-agent.service" "hermes-backend.service"];
    restartTriggers = [gateway];
    environment = {
      HOME = "/var/lib/hermes";
      HERMES_HOME = "/var/lib/hermes/.hermes";
      HERMES_MANAGED = "true";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "hermes";
      Group = "hermes";
      UMask = "0077";
      ExecStart = lib.escapeShellArgs [
        "${config.services.hermes-agent.package.hermesVenv}/bin/python3"
        "${profileSetup}/lib/setup.py"
        "--settings"
        (toString openaiProfile)
        "--credentials"
        "${runtime}/hermes-openai.env"
        "--policy"
        "${./hermes-openai/SOUL.md}"
      ];
    };
  };
  systemd.services.hermes-backend = {
    after = ["inference-credentials.service" "hermes-agent.service" "inference-gateway.service" "hermes-profiles.service"];
    requires = ["inference-credentials.service" "hermes-profiles.service"];
    environment.HERMES_DASHBOARD_PUBLIC_URL = "https://hermes.callumtarttelin.com";
    restartTriggers = [config.age.secrets.hermes-dashboard.file];
    serviceConfig.EnvironmentFile = ["${runtime}/hermes.env" config.age.secrets.hermes-dashboard.path];
  };

  services.caddy.virtualHosts."inference.callumtarttelin.com".extraConfig = ''
    tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
      protocols tls1.3
    }
    @private remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48 127.0.0.1 ::1
    handle @private {
      reverse_proxy 127.0.0.1:8090 {
        flush_interval -1
      }
    }
    handle {
      respond "Tailnet access required" 403
    }
  '';
  services.caddy.virtualHosts."hermes.callumtarttelin.com".extraConfig = ''
    tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
      protocols tls1.3
    }
    @private remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48 127.0.0.1 ::1
    handle @private {
      reverse_proxy 127.0.0.1:9119 {
        header_up -X-Forwarded-Prefix
        flush_interval -1
      }
    }
    handle {
      respond "Tailnet access required" 403
    }
  '';

  environment.systemPackages = [
    pkgs.duckdb
    pkgs.gws
    gateway
    (pkgs.writeShellScriptBin "inference-token" ''
      exec ${pkgs.coreutils}/bin/cat ${runtime}/personal-token
    '')
    (pkgs.writeShellScriptBin "inference-openai-login" ''
      exec sudo -u cliproxyapi ${packages.cliproxyapi}/bin/cliproxyapi \
        -config ${runtime}/cliproxyapi.yaml -codex-device-login
    '')
    (pkgs.writeShellScriptBin "hermes-nixie" ''
      exec sudo -u hermes env HOME=/var/lib/hermes HERMES_HOME=/var/lib/hermes/.hermes \
        PATH=${lib.makeBinPath [hermesGws]}:/etc/profiles/per-user/hermes/bin:/run/current-system/sw/bin \
        ${config.services.hermes-agent.package}/bin/hermes "$@"
    '')
  ];

  # Back up the durable journal as well as Parquet; export is not a prerequisite.
  services.restic.backups.nixie-s3.paths = [state];
  services.restic.backups.nixie-borgbase.paths = [state];
  # Hold the export lock while restic walks the journal/batch/Parquet tree.
  services.restic.backups.nixie-s3.package = lockedRestic;
  services.restic.backups.nixie-borgbase.package = lockedRestic;
}
