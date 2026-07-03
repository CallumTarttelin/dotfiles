_: {
  flake.nixosModules.monitoring = {
    config,
    lib,
    pkgs,
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
              job_name = "caddy";
              scrape_interval = "15s";
              static_configs = [
                {targets = ["localhost:2019"];}
              ];
            }
            {
              job_name = "postgres";
              scrape_interval = "30s";
              static_configs = [
                {targets = ["localhost:9187"];}
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
                    "https://photos.callumtarttelin.com"
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

        # Postgres exporter — forgejo DB metrics
        services.prometheus.exporters.postgres = {
          enable = true;
          port = 9187;
          runAsLocalSuperUser = true;
          dataSourceName = "user=postgres host=/run/postgresql sslmode=disable";
        };

        # Restic backup monitoring — queries actual snapshot timestamps from each repo
        services.prometheus.exporters.node.extraFlags = [
          "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile"
        ];
        systemd.tmpfiles.rules = [
          "z /sys/class/powercap/intel-rapl:*/energy_uj 0444 - - - -"
          "z /sys/class/powercap/intel-rapl:*/*/energy_uj 0444 - - - -"
          "d /var/lib/prometheus-node-exporter/textfile 0755 node-exporter node-exporter - -"
        ];
        systemd.services.restic-snapshot-check = {
          description = "Check restic snapshot ages and write metrics";
          path = with pkgs; [restic jq coreutils];
          script = ''
            set -euo pipefail
            TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"

            check_repo() {
              local name="$1" env_file="$2"
              set -a; source "$env_file"; set +a
              local ts
              ts=$(restic snapshots --latest 1 --json 2>/dev/null \
                | jq -r '.[0].time // empty' \
                | xargs -I{} date -d {} +%s 2>/dev/null || echo "")
              if [ -n "$ts" ]; then
                echo "restic_last_snapshot_timestamp_seconds{repo=\"$name\"} $ts" > "$TEXTFILE_DIR/restic_$name.prom.$$"
                mv "$TEXTFILE_DIR/restic_$name.prom.$$" "$TEXTFILE_DIR/restic_$name.prom"
              fi
            }

            check_repo "nixie-s3" "${config.age.secrets.restic-s3.path}"
            check_repo "nixie-borgbase" "${config.age.secrets.restic-borgbase.path}"
            check_repo "nixshark" "${config.age.secrets.restic-nixshark.path}"
            check_repo "nixwork" "${config.age.secrets.restic-nixwork.path}"
          '';
          serviceConfig.Type = "oneshot";
        };
        systemd.timers.restic-snapshot-check = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*-*-* 02:00:00"; # 1 hour after backups run
            Persistent = true;
          };
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

        # Grafana alerting rules
        services.grafana.provision.alerting = {
          rules.settings = {
            apiVersion = 1;
            groups = [
              {
                orgId = 1;
                name = "Infrastructure";
                folder = "Alerts";
                interval = "1m";
                rules = [
                  {
                    uid = "disk-usage-high";
                    title = "Disk usage > 80%";
                    condition = "C";
                    for = "5m";
                    data = [
                      {
                        refId = "A";
                        datasourceUid = "victoriametrics";
                        model = {
                          expr = "1 - (node_filesystem_avail_bytes{mountpoint=\"/\",fstype!=\"tmpfs\"} / node_filesystem_size_bytes{mountpoint=\"/\",fstype!=\"tmpfs\"})";
                          refId = "A";
                        };
                        relativeTimeRange = {
                          from = 300;
                          to = 0;
                        };
                      }
                      {
                        refId = "C";
                        datasourceUid = "__expr__";
                        model = {
                          type = "threshold";
                          expression = "A";
                          conditions = [
                            {
                              evaluator = {
                                type = "gt";
                                params = [0.8];
                              };
                            }
                          ];
                          refId = "C";
                        };
                      }
                    ];
                    noDataState = "OK";
                    execErrState = "Alerting";
                  }
                  {
                    uid = "service-down";
                    title = "Service down > 5 minutes";
                    condition = "C";
                    for = "5m";
                    data = [
                      {
                        refId = "A";
                        datasourceUid = "victoriametrics";
                        model = {
                          expr = "probe_success == 0";
                          refId = "A";
                        };
                        relativeTimeRange = {
                          from = 300;
                          to = 0;
                        };
                      }
                      {
                        refId = "C";
                        datasourceUid = "__expr__";
                        model = {
                          type = "threshold";
                          expression = "A";
                          conditions = [
                            {
                              evaluator = {
                                type = "gt";
                                params = [0];
                              };
                            }
                          ];
                          refId = "C";
                        };
                      }
                    ];
                    noDataState = "OK";
                    execErrState = "Alerting";
                  }
                  {
                    uid = "backup-stale";
                    title = "Backup older than 2 days";
                    condition = "C";
                    for = "1h";
                    data = [
                      {
                        refId = "A";
                        datasourceUid = "victoriametrics";
                        model = {
                          expr = "time() - restic_last_snapshot_timestamp_seconds > 172800";
                          refId = "A";
                        };
                        relativeTimeRange = {
                          from = 300;
                          to = 0;
                        };
                      }
                      {
                        refId = "C";
                        datasourceUid = "__expr__";
                        model = {
                          type = "threshold";
                          expression = "A";
                          conditions = [
                            {
                              evaluator = {
                                type = "gt";
                                params = [0];
                              };
                            }
                          ];
                          refId = "C";
                        };
                      }
                    ];
                    noDataState = "Alerting";
                    execErrState = "Alerting";
                  }
                  {
                    uid = "high-cpu";
                    title = "High CPU usage sustained > 15 minutes";
                    condition = "C";
                    for = "15m";
                    data = [
                      {
                        refId = "A";
                        datasourceUid = "victoriametrics";
                        model = {
                          expr = "1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))";
                          refId = "A";
                        };
                        relativeTimeRange = {
                          from = 300;
                          to = 0;
                        };
                      }
                      {
                        refId = "C";
                        datasourceUid = "__expr__";
                        model = {
                          type = "threshold";
                          expression = "A";
                          conditions = [
                            {
                              evaluator = {
                                type = "gt";
                                params = [0.9];
                              };
                            }
                          ];
                          refId = "C";
                        };
                      }
                    ];
                    noDataState = "OK";
                    execErrState = "Alerting";
                  }
                  {
                    uid = "high-memory";
                    title = "High memory usage sustained > 15 minutes";
                    condition = "C";
                    for = "15m";
                    data = [
                      {
                        refId = "A";
                        datasourceUid = "victoriametrics";
                        model = {
                          expr = "1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)";
                          refId = "A";
                        };
                        relativeTimeRange = {
                          from = 300;
                          to = 0;
                        };
                      }
                      {
                        refId = "C";
                        datasourceUid = "__expr__";
                        model = {
                          type = "threshold";
                          expression = "A";
                          conditions = [
                            {
                              evaluator = {
                                type = "gt";
                                params = [0.9];
                              };
                            }
                          ];
                          refId = "C";
                        };
                      }
                    ];
                    noDataState = "OK";
                    execErrState = "Alerting";
                  }
                ];
              }
            ];
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
