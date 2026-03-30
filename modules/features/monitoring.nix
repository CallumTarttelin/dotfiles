_: {
  flake.nixosModules.monitoring = {
    config,
    lib,
    ...
  }: let
    cfg = config.features.monitoring;
    tls = ''
      tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
        protocols tls1.3
      }
    '';
  in {
    options.features.monitoring = {
      enable = lib.mkEnableOption "monitoring stack (Victoria Metrics, Grafana, Loki, exporters)";
      node-exporter = lib.mkEnableOption "Prometheus node exporter";
      alloy = lib.mkEnableOption "Grafana Alloy (log shipper to Loki)";
    };

    config = lib.mkMerge [
      # Node exporter — runs on any host that opts in (or has full monitoring enabled)
      (lib.mkIf (cfg.enable || cfg.node-exporter) {
        services.prometheus.exporters.node = {
          enable = true;
          port = 9100;
          enabledCollectors = ["systemd"];
        };
      })

      # Full monitoring stack — nixie only
      (lib.mkIf cfg.enable {
        # Victoria Metrics — single-binary Prometheus-compatible metrics store
        services.victoriametrics = {
          enable = true;
          listenAddress = "127.0.0.1:8428";
          retentionPeriod = "6"; # 6 months
          extraOptions = [
            "-promscrape.config=${config.environment.etc."victoriametrics/scrape.yml".source}"
          ];
        };

        environment.etc."victoriametrics/scrape.yml".text = builtins.toJSON {
          scrape_configs = [
            {
              job_name = "node";
              scrape_interval = "15s";
              static_configs = [
                {
                  targets = [
                    "nixie:9100"
                    "nixshark:9100"
                    "nixwork:9100"
                  ];
                  labels.group = "homelab";
                }
              ];
              relabel_configs = [
                {
                  source_labels = ["__address__"];
                  regex = "([^:]+):.+";
                  target_label = "instance";
                }
              ];
            }
            {
              job_name = "victoriametrics";
              scrape_interval = "15s";
              static_configs = [
                {targets = ["localhost:8428"];}
              ];
            }
            {
              job_name = "blackbox";
              scrape_interval = "60s";
              metrics_path = "/probe";
              params.module = ["http_2xx"];
              static_configs = [
                {
                  targets = [
                    "https://hello.callumtarttelin.com"
                    "https://git.callumtarttelin.com"
                    "https://sync.callumtarttelin.com"
                    "https://vault.callumtarttelin.com"
                    "https://nix-cache.callumtarttelin.com"
                    "https://grafana.callumtarttelin.com"
                    "https://loki.callumtarttelin.com/ready"
                  ];
                }
              ];
              relabel_configs = [
                {
                  source_labels = ["__address__"];
                  target_label = "__param_target";
                }
                {
                  source_labels = ["__param_target"];
                  target_label = "instance";
                }
                {
                  target_label = "__address__";
                  replacement = "localhost:9115";
                }
              ];
            }
          ];
        };

        # Allow node-exporter to read RAPL energy counters (root-only since kernel 5.4).
        # See https://github.com/prometheus/node_exporter/issues/1892
        systemd.tmpfiles.rules = [
          "z /sys/class/powercap/intel-rapl:*/energy_uj 0444 - - - -"
          "z /sys/class/powercap/intel-rapl:*/*/energy_uj 0444 - - - -"
        ];

        # Blackbox exporter — HTTP probes for Caddy services
        services.prometheus.exporters.blackbox = {
          enable = true;
          port = 9115;
          configFile = builtins.toFile "blackbox.yml" (builtins.toJSON {
            modules.http_2xx = {
              prober = "http";
              timeout = "10s";
              http = {
                valid_http_versions = ["HTTP/1.1" "HTTP/2.0"];
                valid_status_codes = [200];
                method = "GET";
                follow_redirects = true;
                preferred_ip_protocol = "ip4";
              };
            };
          });
        };

        # Grafana — dashboards and visualization
        services.grafana = {
          enable = true;
          settings = {
            server = {
              http_addr = "127.0.0.1";
              http_port = 3100;
              domain = "grafana.callumtarttelin.com";
              root_url = "https://grafana.callumtarttelin.com";
            };
            security = {
              admin_password = "$__file{${config.age.secrets.grafana-admin.path}}";
              secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
            };
          };

          provision = {
            enable = true;
            datasources.settings = {
              deleteDatasources = [
                {
                  name = "Victoria Metrics";
                  orgId = 1;
                }
                {
                  name = "Loki";
                  orgId = 1;
                }
              ];
              datasources = [
                {
                  name = "Victoria Metrics";
                  type = "prometheus";
                  uid = "victoriametrics";
                  url = "http://127.0.0.1:8428";
                  isDefault = true;
                  editable = false;
                  orgId = 1;
                }
                {
                  name = "Loki";
                  type = "loki";
                  uid = "loki";
                  url = "http://127.0.0.1:3101";
                  editable = false;
                  orgId = 1;
                }
              ];
            };
            dashboards.settings.providers = [
              {
                name = "Homelab";
                options.path = ./dashboards;
                options.foldersFromFilesStructure = false;
              }
            ];
          };
        };

        # Loki — log aggregation
        services.loki = {
          enable = true;
          configuration = {
            auth_enabled = false;
            server.http_listen_port = 3101;

            common = {
              path_prefix = "/var/lib/loki";
              replication_factor = 1;
              ring.kvstore.store = "inmemory";
            };

            schema_config.configs = [
              {
                from = "2024-01-01";
                store = "tsdb";
                object_store = "filesystem";
                schema = "v13";
                index = {
                  prefix = "index_";
                  period = "24h";
                };
              }
            ];

            storage_config.filesystem.directory = "/var/lib/loki/chunks";

            limits_config = {
              retention_period = "720h"; # 30 days
              allow_structured_metadata = false;
            };

            compactor = {
              working_directory = "/var/lib/loki/compactor";
              delete_request_store = "filesystem";
              retention_enabled = true;
            };
          };
        };

        # Grafana needs to read its agenix secrets
        age.secrets.grafana-admin.owner = "grafana";
        age.secrets.grafana-secret-key.owner = "grafana";

        # Caddy vhosts
        services.caddy.virtualHosts."grafana.callumtarttelin.com".extraConfig = ''
          ${tls}
          reverse_proxy http://localhost:3100
        '';
        services.caddy.virtualHosts."loki.callumtarttelin.com".extraConfig = ''
          ${tls}
          reverse_proxy http://localhost:3101
        '';
        services.caddy.virtualHosts."metrics.callumtarttelin.com".extraConfig = ''
          ${tls}
          reverse_proxy http://localhost:8428
        '';
      })

      # Alloy — log shipper, runs on any host that opts in (or has full monitoring)
      (lib.mkIf (cfg.enable || cfg.alloy) {
        services.alloy = {
          enable = true;
        };

        environment.etc."alloy/config.alloy".text = ''
          loki.relabel "journal" {
            forward_to = []

            rule {
              source_labels = ["__journal__systemd_unit"]
              target_label  = "unit"
            }
            rule {
              source_labels = ["__journal__hostname"]
              target_label  = "host"
            }
            rule {
              source_labels = ["__journal_priority_keyword"]
              target_label  = "level"
            }
          }

          loki.source.journal "read" {
            forward_to    = [loki.write.default.receiver]
            relabel_rules = loki.relabel.journal.rules
            labels        = {job = "journal"}
          }

          loki.write "default" {
            endpoint {
              url = "https://loki.callumtarttelin.com/loki/api/v1/push"
            }
          }
        '';
      })
    ];
  };
}
