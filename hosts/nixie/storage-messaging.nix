{pkgs, ...}: {
  # Local application infrastructure; no Caddy routes, firewall openings or backups.
  services.nats = {
    enable = true;
    serverName = "nixie";
    jetstream = true;
    settings = {
      host = "127.0.0.1";
      http = "127.0.0.1:8222";
      jetstream = {
        max_memory_store = "256M";
        max_file_store = "10G";
      };
    };
  };

  environment.systemPackages = [pkgs.natscli];

  services.garage = {
    enable = true;
    package = pkgs.garage_2;
    settings = {
      db_engine = "sqlite";
      replication_factor = 1;
      rpc_bind_addr = "127.0.0.1:3901";
      rpc_public_addr = "127.0.0.1:3901";
      rpc_secret_file = "/var/lib/garage/rpc-secret";
      s3_api = {
        api_bind_addr = "127.0.0.1:3900";
        s3_region = "garage";
      };
    };
  };

  systemd.services.garage = {
    # Keep the RPC secret out of the Nix store and stable across restarts.
    preStart = ''
      if [ ! -s /var/lib/garage/rpc-secret ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/garage/rpc-secret
      fi
    '';
    serviceConfig = {
      UMask = "0077";
      StateDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
