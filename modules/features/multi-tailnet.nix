{
  flake.nixosModules.multi-tailnet = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.features.multi-tailnet;

    hostAddr = "${cfg.hostAddress}/${toString cfg.prefixLength}";
    namespaceAddr = "${cfg.namespaceAddress}/${toString cfg.prefixLength}";
    namespacePath = "/run/netns/${cfg.namespace}";
    runtimeDir = "/run/${cfg.namespace}";
    sshConfigPath = "${runtimeDir}/ssh_config";

    sudoCommand = "${config.security.wrapperDir}/sudo";
    tailscaleCommand = "${tail2}/bin/${cfg.clientCommand}";
    runtimeConfig = lib.escapeShellArg cfg.runtimeConfigFile;

    validateRuntimeConfig = pkgs.writeShellScriptBin "tail2-validate-config" ''
      set -eu

      config_file="''${1:-${runtimeConfig}}"

      ${pkgs.jq}/bin/jq -e --argjson vncLocalPortBase ${toString cfg.vnc.localPortBase} '
        def is_port:
          type == "number" and . == floor and . >= 1 and . <= 65535;

        def safe_host:
          type == "string" and test("^[A-Za-z0-9_.:-]+$");

        def safe_alias:
          type == "string" and test("^[A-Za-z0-9_.:-]+$");

        def safe_user:
          type == "string" and length > 0 and test("^[A-Za-z0-9_.@+-]+$");

        def scalar:
          type == "string" or type == "number" or type == "boolean";

        def host_valid:
          (.hostName | safe_host)
          and (.user | safe_user)
          and ((.port // 22) | is_port)
          and ((.publicKey // null) == null or (.publicKey | type == "string"))
          and ((.extraOptions // {}) | type == "object" and all(.[]; scalar))
          and (((.localForward // {}) | .enable // false) | type == "boolean")
          and (((.localForward // {}) | .localHost // "127.0.0.1") | safe_host)
          and (((.localForward // {}) | .localPort // 2222) | is_port)
          and (((.vnc // {}) | .enable // false) | type == "boolean")
          and (((.vnc // {}) | .remoteHost // "127.0.0.1") | safe_host)
          and (((.vnc // {}) | .remotePort // 5900) | is_port)
          and (((.vnc // {}) | .localPort // null) == null or (((.vnc // {}) | .localPort) | is_port))
          and (((.vnc // {}) | .profileOptions // {}) | type == "object" and all(.[]; scalar));

        def local_forward_ports:
          [
            .hosts
            | to_entries[]
            | select((.value.localForward.enable // false) == true)
            | (.value.localForward.localPort // 2222)
          ];

        def vnc_ports:
          [
            .hosts
            | to_entries
            | sort_by(.key)
            | to_entries[]
            | select((.value.value.vnc.enable // false) == true)
            | (.value.value.vnc.localPort // ($vncLocalPortBase + .key))
          ];

        type == "object"
        and (.hosts | type == "object")
        and (.hosts | to_entries | all(.key | safe_alias))
        and (.hosts | to_entries | all(.value | host_valid))
        and ((local_forward_ports | length) == (local_forward_ports | unique | length))
        and ((vnc_ports | length) == (vnc_ports | unique | length))
      ' "$config_file" >/dev/null
    '';

    renderSshConfig = pkgs.writeShellScriptBin "tail2-render-ssh-config" ''
      set -eu

      config_file="''${1:-${runtimeConfig}}"
      output_file="''${2:-${sshConfigPath}}"
      output_dir="$(${pkgs.coreutils}/bin/dirname "$output_file")"
      tmp_file="$output_file.tmp.$$"

      ${validateRuntimeConfig}/bin/tail2-validate-config "$config_file"
      ${pkgs.coreutils}/bin/mkdir -p "$output_dir"
      ${pkgs.coreutils}/bin/chmod 0755 "$output_dir"

      ${pkgs.jq}/bin/jq -r --arg proxy "${sudoCommand} -n ${tail2Connect}/bin/tail2-connect %h %p" '
        def ssh_value:
          if type == "boolean" then
            if . then "yes" else "no" end
          else
            tostring
          end;

        .hosts
        | to_entries
        | sort_by(.key)
        | .[]
        | [
            "Host \(.key)",
            "  HostName \(.value.hostName)",
            "  User \(.value.user)",
            "  Port \(.value.port // 22)",
            "  ProxyCommand \($proxy)",
            "  CheckHostIP no",
            (
              .value.extraOptions // {}
              | to_entries
              | sort_by(.key)
              | .[]
              | "  \(.key) \(.value | ssh_value)"
            ),
            ""
          ]
        | .[]
      ' "$config_file" >"$tmp_file"

      ${pkgs.coreutils}/bin/chmod 0644 "$tmp_file"
      ${pkgs.coreutils}/bin/mv "$tmp_file" "$output_file"
    '';

    setupNamespace = pkgs.writeShellScript "setup-${cfg.namespace}-tailnet" ''
      set -eu

      ${pkgs.iproute2}/bin/ip netns add ${cfg.namespace} 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link set lo up

      for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
        if ${pkgs.iproute2}/bin/ip link show ${cfg.namespaceVeth} >/dev/null 2>&1; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      if ${pkgs.iproute2}/bin/ip link show ${cfg.namespaceVeth} >/dev/null 2>&1; then
        ${pkgs.iproute2}/bin/ip link set ${cfg.namespaceVeth} netns ${cfg.namespace}
      fi

      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} addr replace ${namespaceAddr} dev ${cfg.namespaceVeth}
      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link set ${cfg.namespaceVeth} up
      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} route replace default via ${cfg.hostAddress}
    '';

    cleanupNamespace = pkgs.writeShellScript "cleanup-${cfg.namespace}-tailnet" ''
      set +e

      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link del ${cfg.namespaceVeth}
      ${pkgs.iproute2}/bin/ip netns del ${cfg.namespace}
    '';

    tail2 = pkgs.writeShellScriptBin cfg.clientCommand ''
      exec ${pkgs.tailscale}/bin/tailscale --socket ${cfg.socketPath} "$@"
    '';

    tail2Connect = pkgs.writeShellScriptBin "tail2-connect" ''
      set -eu

      if [ "$#" -ne 2 ]; then
        echo "usage: tail2-connect <host> <port>" >&2
        exit 64
      fi

      host="$1"
      port="$2"

      if ! printf '%s\n' "$host" | ${pkgs.gnugrep}/bin/grep -Eq '^[A-Za-z0-9_.:-]+$'; then
        echo "invalid host: $host" >&2
        exit 64
      fi

      if ! printf '%s\n' "$port" | ${pkgs.gnugrep}/bin/grep -Eq '^[0-9]+$'; then
        echo "invalid port: $port" >&2
        exit 64
      fi

      if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "invalid port: $port" >&2
        exit 64
      fi

      exec ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.netcat-openbsd}/bin/nc "$host" "$port"
    '';

    tail2Ssh = pkgs.writeShellScriptBin cfg.sshCommand ''
      set -eu

      if [ ! -s ${lib.escapeShellArg sshConfigPath} ]; then
        ${renderSshConfig}/bin/tail2-render-ssh-config
      fi

      exec ${pkgs.openssh}/bin/ssh \
        -F ${lib.escapeShellArg sshConfigPath} \
        "$@"
    '';

    tail2LocalForwards = pkgs.writeShellScriptBin "tail2-local-forwards" ''
      set -eu

      config_file=${runtimeConfig}
      pids=""

      cleanup() {
        for pid in $pids; do
          kill "$pid" >/dev/null 2>&1 || true
        done
        wait >/dev/null 2>&1 || true
      }

      trap cleanup EXIT INT TERM

      ${validateRuntimeConfig}/bin/tail2-validate-config "$config_file"
      ${renderSshConfig}/bin/tail2-render-ssh-config "$config_file" ${lib.escapeShellArg sshConfigPath}

      hosts_file="$(${pkgs.coreutils}/bin/mktemp)"
      ${pkgs.jq}/bin/jq -r '
        .hosts
        | to_entries
        | sort_by(.key)
        | .[]
        | select((.value.localForward.enable // false) == true)
        | [
            .key,
            .value.hostName,
            (.value.port // 22),
            (.value.localForward.localHost // "127.0.0.1"),
            (.value.localForward.localPort // 2222)
          ]
        | @tsv
      ' "$config_file" >"$hosts_file"

      while IFS=$'\t' read -r alias host port local_host local_port; do
        [ -n "$alias" ] || continue
        ${pkgs.socat}/bin/socat \
          "TCP-LISTEN:$local_port,bind=$local_host,reuseaddr,fork" \
          "EXEC:${tail2Connect}/bin/tail2-connect $host $port,nofork" &
        pids="$pids $!"
      done <"$hosts_file"
      ${pkgs.coreutils}/bin/rm -f "$hosts_file"

      if [ -z "$pids" ]; then
        exec ${pkgs.coreutils}/bin/sleep infinity
      fi

      wait
    '';

    tail2VncTunnel = pkgs.writeShellScriptBin "tail2-vnc-tunnel" ''
      set -eu

      if [ "$#" -ne 2 ]; then
        echo "usage: tail2-vnc-tunnel <alias> <start|stop>" >&2
        exit 64
      fi

      alias="$1"
      action="$2"
      config_file=${runtimeConfig}

      ${validateRuntimeConfig}/bin/tail2-validate-config "$config_file"

      if ! printf '%s\n' "$alias" | ${pkgs.gnugrep}/bin/grep -Eq '^[A-Za-z0-9_.:-]+$'; then
        echo "invalid VNC host: $alias" >&2
        exit 64
      fi

      host_json="$(${pkgs.jq}/bin/jq -e --arg alias "$alias" '.hosts[$alias] | select(. != null and (.vnc.enable // false) == true)' "$config_file")" || {
        echo "unknown VNC host: $alias" >&2
        exit 64
      }

      vnc_index="$(${pkgs.jq}/bin/jq -r --arg alias "$alias" '
        [
          .hosts
          | to_entries
          | sort_by(.key)
          | .[]
          | select((.value.vnc.enable // false) == true)
          | .key
        ]
        | index($alias)
      ' "$config_file")"

      remote_host="$(printf '%s\n' "$host_json" | ${pkgs.jq}/bin/jq -r '.vnc.remoteHost // "127.0.0.1"')"
      remote_port="$(printf '%s\n' "$host_json" | ${pkgs.jq}/bin/jq -r '.vnc.remotePort // 5900')"
      local_port="$(printf '%s\n' "$host_json" | ${pkgs.jq}/bin/jq -r --argjson vncIndex "$vnc_index" --argjson vncLocalPortBase ${toString cfg.vnc.localPortBase} '.vnc.localPort // ($vncLocalPortBase + $vncIndex)')"

      ${renderSshConfig}/bin/tail2-render-ssh-config "$config_file" ${lib.escapeShellArg sshConfigPath}

      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/tail2-vnc"
      control_socket="$runtime_dir/$alias.ctl"

      case "$action" in
        start)
          ${pkgs.coreutils}/bin/mkdir -p "$runtime_dir"
          if [ -S "$control_socket" ]; then
            if ${pkgs.openssh}/bin/ssh -F ${lib.escapeShellArg sshConfigPath} -S "$control_socket" -O check "$alias" >/dev/null 2>&1; then
              exit 0
            fi
            ${pkgs.coreutils}/bin/rm -f "$control_socket"
          fi

          exec ${pkgs.openssh}/bin/ssh \
            -F ${lib.escapeShellArg sshConfigPath} \
            -f \
            -N \
            -M \
            -S "$control_socket" \
            -L "127.0.0.1:$local_port:$remote_host:$remote_port" \
            -o ExitOnForwardFailure=yes \
            -o ControlMaster=yes \
            "$alias"
          ;;
        stop)
          if [ -S "$control_socket" ]; then
            ${pkgs.openssh}/bin/ssh -F ${lib.escapeShellArg sshConfigPath} -S "$control_socket" -O exit "$alias" >/dev/null 2>&1 || true
            ${pkgs.coreutils}/bin/rm -f "$control_socket"
          fi
          ;;
        *)
          echo "unknown action: $action" >&2
          exit 64
          ;;
      esac
    '';

    tail2Vnc = pkgs.writeShellScriptBin cfg.vnc.command ''
      set -eu

      config_file=${runtimeConfig}

      ${validateRuntimeConfig}/bin/tail2-validate-config "$config_file"

      list_hosts() {
        ${pkgs.jq}/bin/jq -r '
          .hosts
          | to_entries
          | sort_by(.key)
          | .[]
          | select((.value.vnc.enable // false) == true)
          | .key
        ' "$config_file"
      }

      usage() {
        echo "usage: ${cfg.vnc.command} <host>|--list|--show <host>" >&2
        echo "available hosts:" >&2
        list_hosts >&2
      }

      if [ "$#" -eq 1 ] && [ "$1" = "--list" ]; then
        list_hosts
        exit 0
      fi

      if [ "$#" -eq 2 ] && [ "$1" = "--show" ]; then
        alias="$2"
        host_json="$(${pkgs.jq}/bin/jq -e --arg alias "$alias" '.hosts[$alias] | select(. != null and (.vnc.enable // false) == true)' "$config_file")" || {
          echo "unknown VNC host: $alias" >&2
          exit 64
        }
        vnc_index="$(${pkgs.jq}/bin/jq -r --arg alias "$alias" '
          [
            .hosts
            | to_entries
            | sort_by(.key)
            | .[]
            | select((.value.vnc.enable // false) == true)
            | .key
          ]
          | index($alias)
        ' "$config_file")"
        remote_host="$(printf '%s\n' "$host_json" | ${pkgs.jq}/bin/jq -r '.vnc.remoteHost // "127.0.0.1"')"
        remote_port="$(printf '%s\n' "$host_json" | ${pkgs.jq}/bin/jq -r '.vnc.remotePort // 5900')"
        local_port="$(printf '%s\n' "$host_json" | ${pkgs.jq}/bin/jq -r --argjson vncIndex "$vnc_index" --argjson vncLocalPortBase ${toString cfg.vnc.localPortBase} '.vnc.localPort // ($vncLocalPortBase + $vncIndex)')"

        printf 'alias=%s\n' "$alias"
        printf 'remote=%s:%s\n' "$remote_host" "$remote_port"
        printf 'local=127.0.0.1:%s\n' "$local_port"
        exit 0
      fi

      if [ "$#" -ne 1 ]; then
        usage
        exit 64
      fi

      alias="$1"
      host_json="$(${pkgs.jq}/bin/jq -e --arg alias "$alias" '.hosts[$alias] | select(. != null and (.vnc.enable // false) == true)' "$config_file")" || {
        usage
        exit 64
      }
      vnc_index="$(${pkgs.jq}/bin/jq -r --arg alias "$alias" '
        [
          .hosts
          | to_entries
          | sort_by(.key)
          | .[]
          | select((.value.vnc.enable // false) == true)
          | .key
        ]
        | index($alias)
      ' "$config_file")"
      local_port="$(printf '%s\n' "$host_json" | ${pkgs.jq}/bin/jq -r --argjson vncIndex "$vnc_index" --argjson vncLocalPortBase ${toString cfg.vnc.localPortBase} '.vnc.localPort // ($vncLocalPortBase + $vncIndex)')"

      runtime_root="''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}/tail2-remmina-$(${pkgs.coreutils}/bin/id -u)}"
      runtime_dir="$runtime_root/tail2-remmina"
      profile="$runtime_dir/$alias.remmina"

      ${pkgs.coreutils}/bin/mkdir -p "$runtime_dir"
      {
        printf '[remmina]\n'
        printf 'name=%s\n' "$alias"
        printf 'protocol=VNC\n'
        printf 'server=127.0.0.1:%s\n' "$local_port"
        printf 'precommand=%s %s start\n' "${tail2VncTunnel}/bin/tail2-vnc-tunnel" "$alias"
        printf 'postcommand=%s %s stop\n' "${tail2VncTunnel}/bin/tail2-vnc-tunnel" "$alias"
        printf '%s\n' "$host_json" | ${pkgs.jq}/bin/jq -r '
          def remmina_value:
            if type == "boolean" then tostring else tostring end;

          .vnc.profileOptions // {}
          | to_entries
          | sort_by(.key)
          | .[]
          | "\(.key)=\(.value | remmina_value)"
        '
      } >"$profile"
      ${pkgs.coreutils}/bin/chmod 0600 "$profile"

      exec ${cfg.vnc.viewer.package}/bin/${cfg.vnc.viewer.executable} -c "$profile"
    '';
  in {
    options.features.multi-tailnet = {
      enable = lib.mkEnableOption "a second Tailscale tailnet in a network namespace";

      runtimeConfigFile = lib.mkOption {
        type = lib.types.path;
        description = "Runtime JSON config file containing secondary tailnet host details.";
      };

      namespace = lib.mkOption {
        type = lib.types.str;
        default = "tail2";
      };

      hostVeth = lib.mkOption {
        type = lib.types.str;
        default = "veth-tail2-host";
      };

      namespaceVeth = lib.mkOption {
        type = lib.types.str;
        default = "veth-tail2-ns";
      };

      tailscaleInterface = lib.mkOption {
        type = lib.types.str;
        default = "tailscale0";
      };

      vethSubnet = lib.mkOption {
        type = lib.types.str;
        default = "192.168.101.0/24";
      };

      hostAddress = lib.mkOption {
        type = lib.types.str;
        default = "192.168.101.1";
      };

      namespaceAddress = lib.mkOption {
        type = lib.types.str;
        default = "192.168.101.2";
      };

      prefixLength = lib.mkOption {
        type = lib.types.int;
        default = 24;
      };

      sshUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["tarttelin"];
        description = "Local users allowed to open SSH proxy connections through the secondary tailnet namespace.";
      };

      vnc = {
        enable = lib.mkEnableOption "VNC access to secondary tailnet hosts";

        command = lib.mkOption {
          type = lib.types.str;
          default = "tail2-vnc";
        };

        localPortBase = lib.mkOption {
          type = lib.types.port;
          default = 15900;
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [pkgs.libvncserver];
          defaultText = lib.literalExpression "[pkgs.libvncserver]";
          description = "Extra packages installed with VNC support.";
        };

        viewer = {
          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.remmina;
            defaultText = lib.literalExpression "pkgs.remmina";
          };

          executable = lib.mkOption {
            type = lib.types.str;
            default = "remmina";
          };

          backend = lib.mkOption {
            type = lib.types.enum ["remmina-profile"];
            default = "remmina-profile";
          };
        };
      };

      authKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional file containing a Tailscale auth key for unattended secondary tailnet login.";
      };

      authKeyParameters = lib.mkOption {
        type = lib.types.attrsOf (lib.types.oneOf [
          lib.types.str
          lib.types.int
          lib.types.bool
        ]);
        default = {};
        description = "Optional query parameters appended to the auth key.";
      };

      extraUpFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["--accept-routes"];
        description = "Flags passed to tailscale up for the secondary tailnet.";
      };

      socketPath = lib.mkOption {
        type = lib.types.str;
        default = "/run/tail2/tailscaled.sock";
      };

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/tail2";
      };

      clientCommand = lib.mkOption {
        type = lib.types.str;
        default = "tail2";
      };

      sshCommand = lib.mkOption {
        type = lib.types.str;
        default = "tail2-ssh";
      };
    };

    config = lib.mkIf cfg.enable {
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

      environment.systemPackages =
        [
          tail2
          tail2Ssh
          tail2Connect
          renderSshConfig
          validateRuntimeConfig
        ]
        ++ lib.optionals cfg.vnc.enable [
          cfg.vnc.viewer.package
          tail2VncTunnel
          tail2Vnc
        ]
        ++ cfg.vnc.extraPackages;

      assertions = [
        {
          assertion = cfg.vnc.viewer.backend != "remmina-profile" || cfg.vnc.viewer.executable == "remmina";
          message = "features.multi-tailnet.vnc.viewer.backend = \"remmina-profile\" requires viewer.executable = \"remmina\".";
        }
      ];

      networking = {
        firewall.extraForwardRules = ''
          iifname "${cfg.hostVeth}" oifname != "${cfg.hostVeth}" accept
          oifname "${cfg.hostVeth}" ct state established,related accept
        '';

        nftables.tables."tail2-nat" = {
          family = "ip";
          name = "tail2_nat";
          content = ''
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              ip saddr ${cfg.vethSubnet} oifname != "${cfg.hostVeth}" masquerade
            }
          '';
        };
      };

      programs.ssh.extraConfig = ''
        Include ${sshConfigPath}
      '';

      security.sudo.extraRules = lib.mkIf (cfg.sshUsers != []) [
        {
          users = cfg.sshUsers;
          commands = [
            {
              command = "${tail2Connect}/bin/tail2-connect *";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];

      systemd = {
        network = {
          netdevs."10-${cfg.namespace}" = {
            netdevConfig = {
              Kind = "veth";
              Name = cfg.hostVeth;
            };
            peerConfig.Name = cfg.namespaceVeth;
          };

          networks."10-${cfg.namespace}-host" = {
            matchConfig.Name = cfg.hostVeth;
            address = [hostAddr];
            linkConfig.RequiredForOnline = "no";
            networkConfig.IPv4Forwarding = "yes";
          };
        };

        tmpfiles.rules = [
          "d ${runtimeDir} 0755 root root -"
          "f ${sshConfigPath} 0644 root root -"
          "d ${cfg.stateDir} 0700 root root -"
        ];

        services =
          {
            "${cfg.namespace}-netns" = {
              description = "Network namespace for ${cfg.namespace} Tailscale";
              wantedBy = ["multi-user.target"];
              before = ["tailscaled-${cfg.namespace}.service"];
              after = ["systemd-networkd.service"];
              wants = ["systemd-networkd.service"];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = setupNamespace;
                ExecStop = cleanupNamespace;
              };
            };

            "tailscaled-${cfg.namespace}" = {
              description = "Tailscale daemon for ${cfg.namespace}";
              wantedBy = ["multi-user.target"];
              after = ["${cfg.namespace}-netns.service"];
              requires = ["${cfg.namespace}-netns.service"];
              serviceConfig = {
                NetworkNamespacePath = namespacePath;
                ExecStart = "${pkgs.tailscale}/bin/tailscaled --tun ${cfg.tailscaleInterface} --socket ${cfg.socketPath} --statedir=${cfg.stateDir} --state=${cfg.stateDir}/tailscaled.state";
                Restart = "on-failure";
                RuntimeDirectory = cfg.namespace;
                StateDirectory = baseNameOf cfg.stateDir;
              };
            };

            "${cfg.namespace}-runtime-config" = {
              description = "Render ${cfg.namespace} SSH runtime config";
              wantedBy = ["multi-user.target"];
              after = ["agenix.service"];
              wants = ["agenix.service"];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${renderSshConfig}/bin/tail2-render-ssh-config";
              };
            };

            "${cfg.namespace}-local-forwards" = {
              description = "Local SSH proxies for ${cfg.namespace}";
              wantedBy = ["multi-user.target"];
              after = [
                "${cfg.namespace}-netns.service"
                "tailscaled-${cfg.namespace}.service"
                "${cfg.namespace}-runtime-config.service"
              ];
              wants = [
                "tailscaled-${cfg.namespace}.service"
                "${cfg.namespace}-runtime-config.service"
              ];
              serviceConfig = {
                ExecStart = "${tail2LocalForwards}/bin/tail2-local-forwards";
                Restart = "on-failure";
                RestartSec = "2s";
              };
            };
          }
          // lib.optionalAttrs (cfg.authKeyFile != null) {
            "tailscaled-${cfg.namespace}-autoconnect" = {
              description = "Authenticate ${cfg.namespace} Tailscale";
              wantedBy = ["multi-user.target"];
              after = ["tailscaled-${cfg.namespace}.service"];
              wants = ["tailscaled-${cfg.namespace}.service"];
              path = [
                tail2
                pkgs.jq
              ];
              serviceConfig.Type = "notify";
              script = let
                paramToString = value:
                  if builtins.isBool value
                  then lib.boolToString value
                  else toString value;
                params = lib.pipe cfg.authKeyParameters [
                  (lib.filterAttrs (_: value: value != null))
                  (lib.mapAttrsToList (key: value: "${key}=${paramToString value}"))
                  (builtins.concatStringsSep "&")
                  (value:
                    if value == ""
                    then ""
                    else "?${value}")
                ];
              in ''
                getState() {
                  ${tailscaleCommand} status --json --peers=false | ${pkgs.jq}/bin/jq -r '.BackendState'
                }

                lastState=""
                while state="$(getState)"; do
                  if [ "$state" != "$lastState" ]; then
                    case "$state" in
                      NeedsLogin|NeedsMachineAuth|Stopped)
                        ${tailscaleCommand} up --auth-key "$(${pkgs.coreutils}/bin/cat ${cfg.authKeyFile})${params}" ${lib.escapeShellArgs cfg.extraUpFlags}
                        ;;
                      Running)
                        ${pkgs.systemd}/bin/systemd-notify --ready
                        exit 0
                        ;;
                    esac
                  fi

                  lastState="$state"
                  ${pkgs.coreutils}/bin/sleep 0.5
                done
              '';
            };
          };
      };
    };
  };
}
