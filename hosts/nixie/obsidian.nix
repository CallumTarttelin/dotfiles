{
  config,
  pkgs,
  ...
}: {
  age.secrets.couchdb-admin = {
    file = ../../secrets/couchdb-admin.age;
    owner = "couchdb";
  };
  age.secrets.livesync-client.file = ../../secrets/livesync-client.age;

  services.couchdb = {
    enable = true;
    bindAddress = "127.0.0.1";
    extraConfigFiles = [config.age.secrets.couchdb-admin.path];
    extraConfig = {
      couchdb = {
        single_node = true;
        max_document_size = 50000000;
      };
      cluster = {
        n = 1;
        q = 1;
      };
      chttpd = {
        require_valid_user_except_for_up = true;
        enable_cors = true;
        max_http_request_size = 4294967296;
      };
      chttpd_auth.require_valid_user = true;
      httpd = {
        enable_cors = true;
        "WWW-Authenticate" = "Basic realm=\"couchdb\"";
      };
      cors = {
        credentials = true;
        origins = "app://obsidian.md,capacitor://localhost,http://localhost";
      };
      log = {
        writer = "stderr";
        level = "warning";
      };
    };
  };

  systemd.services.couchdb = {
    environment = {
      ERL_EPMD_ADDRESS = "127.0.0.1";
      # Notes are an intermittent workload. Sleeping idle schedulers avoids
      # spending CPU spinning between requests and CouchDB's periodic tasks.
      # Two schedulers are sufficient for a few vaults and reduce runtime
      # housekeeping compared with using all 20 logical CPUs on nixie.
      ERL_AFLAGS = "+S 2:2 +sbwt none +sbwtdcpu none +sbwtdio none -kernel inet_dist_use_interface {127,0,0,1}";
    };
    restartTriggers = [config.age.secrets.couchdb-admin.file];
    serviceConfig = {
      UMask = "0077";
      StateDirectory = "couchdb";
      StateDirectoryMode = "0700";
      MemoryAccounting = true;
      TasksAccounting = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.couchdb-livesync-init = {
    description = "Provision LiveSync databases and its server administrator account";
    wantedBy = ["multi-user.target"];
    requires = ["couchdb.service"];
    partOf = ["couchdb.service"];
    after = ["couchdb.service"];
    restartTriggers = [config.age.secrets.livesync-client.file config.age.secrets.couchdb-admin.file];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
      LoadCredential = [
        "admin.ini:${config.age.secrets.couchdb-admin.path}"
        "client.json:${config.age.secrets.livesync-client.path}"
      ];
      ExecStart = "${pkgs.python3}/bin/python3 ${./livesync-init.py} personal work";
    };
  };

  services.caddy.virtualHosts."obsidian.callumtarttelin.com".extraConfig = ''
    tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
      protocols tls1.3
    }
    @outside not remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48 127.0.0.1 ::1
    respond @outside "Tailscale access required" 403
    reverse_proxy http://127.0.0.1:5984
  '';

  # CouchDB's append-only database files support online file backups. Include
  # local.ini too: CouchDB persists runtime configuration and admin hashes here.
  services.restic.backups.nixie-s3.paths = ["/var/lib/couchdb"];
  services.restic.backups.nixie-borgbase.paths = ["/var/lib/couchdb"];

  # Reuse the node exporter's textfile collector; no extra exporter daemon.
  systemd.services.couchdb-resource-metrics = {
    description = "Record CouchDB service CPU, memory and storage usage";
    after = ["couchdb.service"];
    path = [pkgs.systemd pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${./couchdb-resource-metrics.py}";
      UMask = "0022";
    };
  };
  systemd.timers.couchdb-resource-metrics = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
  };
}
