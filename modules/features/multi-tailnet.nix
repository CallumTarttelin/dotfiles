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
    sshConfigDir = "/run/${cfg.namespace}-ssh";
    sshConfigPath = "${sshConfigDir}/ssh_config";
    routeStatePath = "${runtimeDir}/routes.state";
    legacyRouteStatePath = "${runtimeDir}/direct-routes";
    nftStatePath = "${runtimeDir}/tail2-publish.nft";

    runtimeConfig = lib.escapeShellArg cfg.runtimeConfigFile;

    validateRuntimeConfig = pkgs.writeShellScriptBin "tail2-validate-config" ''
      set -eu

      config_file="''${1:-${runtimeConfig}}"

      ${pkgs.jq}/bin/jq -e '
        def is_port:
          type == "number" and . == floor and . >= 1 and . <= 65535;

        def safe_alias:
          type == "string" and length > 0 and test("^[A-Za-z0-9_.-]+$");

        def safe_target:
          type == "string" and length > 0 and test("^[A-Za-z0-9_.-]+\\.?$");

        def safe_user:
          type == "string" and length > 0 and test("^[A-Za-z0-9_.@+-]+$");

        def scalar:
          type == "string" or type == "number" or type == "boolean";

        def host_valid:
          type == "object"
          and ((keys_unsorted - ["target", "user", "port", "extraOptions"]) | length == 0)
          and (.target | safe_target)
          and ((.user // null) == null or (.user | safe_user))
          and ((.port // 22) | is_port)
          and ((.extraOptions // {}) | type == "object" and all(.[]; scalar));

        type == "object"
        and (.hosts | type == "object")
        and (.hosts | to_entries | all(.key | safe_alias))
        and (.hosts | to_entries | all(.value | host_valid))
      ' "$config_file" >/dev/null
    '';

    setupNamespace = pkgs.writeShellScript "setup-${cfg.namespace}-tailnet" ''
      set -eu

      ${pkgs.iproute2}/bin/ip netns add ${cfg.namespace} 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link set lo up

      if ! ${pkgs.iproute2}/bin/ip link show ${cfg.hostVeth} >/dev/null 2>&1 \
        && ! ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link show ${cfg.namespaceVeth} >/dev/null 2>&1; then
        ${pkgs.iproute2}/bin/ip link add ${cfg.hostVeth} type veth peer name ${cfg.namespaceVeth}
      fi

      for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
        if ${pkgs.iproute2}/bin/ip link show ${cfg.namespaceVeth} >/dev/null 2>&1 \
          || ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link show ${cfg.namespaceVeth} >/dev/null 2>&1; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      if ${pkgs.iproute2}/bin/ip link show ${cfg.namespaceVeth} >/dev/null 2>&1; then
        ${pkgs.iproute2}/bin/ip link set ${cfg.namespaceVeth} netns ${cfg.namespace}
      fi

      ${pkgs.iproute2}/bin/ip addr replace ${hostAddr} dev ${cfg.hostVeth}
      ${pkgs.iproute2}/bin/ip link set ${cfg.hostVeth} up
      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} addr replace ${namespaceAddr} dev ${cfg.namespaceVeth}
      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link set ${cfg.namespaceVeth} up
      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} route replace default via ${cfg.hostAddress}
      ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=1 >/dev/null
      ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null
      ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.default.forwarding=1 >/dev/null
      ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
      ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null
      ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.${cfg.namespaceVeth}.forwarding=1 >/dev/null
      ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.${cfg.namespaceVeth}.rp_filter=0 >/dev/null
    '';

    cleanupNamespace = pkgs.writeShellScript "cleanup-${cfg.namespace}-tailnet" ''
      set +e

      ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link del ${cfg.namespaceVeth}
      ${pkgs.iproute2}/bin/ip netns del ${cfg.namespace}
    '';

    tail2 = pkgs.writeShellScriptBin cfg.clientCommand ''
      exec ${pkgs.tailscale}/bin/tailscale --socket ${cfg.socketPath} "$@"
    '';

    tail2Publish = pkgs.writeShellScriptBin "${cfg.namespace}-publish" ''
            set -eu

            log() {
              printf '${cfg.namespace}-publish: %s\n' "$*" >&2
            }

            config_file="''${1:-${runtimeConfig}}"
            hosts_file="/etc/hosts"
            route_state=${lib.escapeShellArg routeStatePath}
            legacy_route_state=${lib.escapeShellArg legacyRouteStatePath}
            nft_state=${lib.escapeShellArg nftStatePath}
            ssh_config=${lib.escapeShellArg sshConfigPath}
            work_dir="$(${pkgs.coreutils}/bin/mktemp -d)"
            tmp_hosts=""
            tmp_ssh=""

            cleanup() {
              ${pkgs.coreutils}/bin/rm -rf "$work_dir"
              if [ -n "$tmp_hosts" ]; then
                ${pkgs.coreutils}/bin/rm -f "$tmp_hosts"
              fi
              if [ -n "$tmp_ssh" ]; then
                ${pkgs.coreutils}/bin/rm -f "$tmp_ssh"
              fi
            }

            trap cleanup EXIT INT TERM

            ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg runtimeDir} ${lib.escapeShellArg sshConfigDir}

            log "validating alias config at $config_file"
            ${validateRuntimeConfig}/bin/tail2-validate-config "$config_file"

            log "reading primary tailnet status"
            ${pkgs.tailscale}/bin/tailscale status --json >"$work_dir/primary.json"
            log "reading secondary tailnet status"
            if ! ${tail2}/bin/${cfg.clientCommand} status --json >"$work_dir/secondary.json"; then
              log "secondary tailnet status unavailable; publishing empty access"
              printf '{"BackendState":"Unavailable","Peer":{}}\n' >"$work_dir/secondary.json"
            fi

            export TAIL2_NAMESPACE=${lib.escapeShellArg cfg.namespace}
            export TAIL2_NAMESPACE_VETH=${lib.escapeShellArg cfg.namespaceVeth}
            export TAIL2_TAILSCALE_INTERFACE=${lib.escapeShellArg cfg.tailscaleInterface}
            export TAIL2_VETH_SUBNET=${lib.escapeShellArg cfg.vethSubnet}

            log "enabling namespace forwarding"
            ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=1 >/dev/null
            ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null
            ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.default.forwarding=1 >/dev/null
            ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
            ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null
            for iface in ${lib.escapeShellArg cfg.namespaceVeth} ${lib.escapeShellArg cfg.tailscaleInterface}; do
              if ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link show "$iface" >/dev/null 2>&1; then
                ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w "net.ipv4.conf.$iface.forwarding=1" >/dev/null
                ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.procps}/bin/sysctl -w "net.ipv4.conf.$iface.rp_filter=0" >/dev/null
              fi
            done

            ${pkgs.python3}/bin/python3 - "$config_file" "$work_dir/primary.json" "$work_dir/secondary.json" "$work_dir" <<'PY'
      import collections
      import ipaddress
      import json
      import os
      import pathlib
      import sys

      config_path, primary_path, secondary_path, work_dir = sys.argv[1:5]
      namespace = os.environ["TAIL2_NAMESPACE"]
      namespace_veth = os.environ["TAIL2_NAMESPACE_VETH"]
      tailscale_interface = os.environ["TAIL2_TAILSCALE_INTERFACE"]
      veth_subnet = os.environ["TAIL2_VETH_SUBNET"]
      work = pathlib.Path(work_dir)


      def load_json(path):
          with open(path, encoding="utf-8") as handle:
              return json.load(handle)


      def status_nodes(status, include_self):
          nodes = []
          if include_self and isinstance(status.get("Self"), dict):
              nodes.append(status["Self"])
          peer = status.get("Peer") or {}
          if isinstance(peer, dict):
              nodes.extend(value for value in peer.values() if isinstance(value, dict))
          return nodes


      def first_ipv4(node):
          for value in node.get("TailscaleIPs") or []:
              try:
                  return str(ipaddress.IPv4Address(value))
              except ipaddress.AddressValueError:
                  continue
          return None


      def dns_name(node):
          value = node.get("DNSName")
          if not isinstance(value, str) or not value:
              return None
          return value.rstrip(".").lower()


      def dns_label(node):
          value = dns_name(node)
          if not value:
              return None
          return value.split(".", 1)[0]


      def add_unique(items, value):
          if value not in items:
              items.append(value)


      def fail(message):
          print(f"{namespace}-publish: {message}", file=sys.stderr)
          sys.exit(1)


      primary = load_json(primary_path)
      secondary = load_json(secondary_path)
      alias_config = load_json(config_path)

      primary_nodes = status_nodes(primary, include_self=True)
      primary_ips = {ip for node in primary_nodes if (ip := first_ipv4(node))}
      primary_labels = {label for node in primary_nodes if (label := dns_label(node))}
      secondary_state = secondary.get("BackendState")
      secondary_self_ip = first_ipv4(secondary.get("Self") or {})
      secondary_running = secondary_state == "Running" and secondary_self_ip is not None
      if not secondary_running:
          print(
              f"{namespace}-publish: secondary tailnet is not running; publishing empty access",
              file=sys.stderr,
          )

      secondary_entries = []
      if secondary_running:
          for node in status_nodes(secondary, include_self=False):
              ip = first_ipv4(node)
              fqdn = dns_name(node)
              if not ip or not fqdn:
                  continue
              if ip in primary_ips:
                  continue
              label = fqdn.split(".", 1)[0]
              secondary_entries.append({"ip": ip, "fqdn": fqdn, "label": label})

      label_counts = collections.Counter(entry["label"] for entry in secondary_entries)
      target_map = collections.defaultdict(list)
      generated_by_ip = collections.defaultdict(list)
      generated_owner = {}

      for entry in sorted(secondary_entries, key=lambda item: (ipaddress.IPv4Address(item["ip"]), item["fqdn"])):
          aliases = [entry["fqdn"], f"{entry['label']}.{namespace}"]
          if label_counts[entry["label"]] == 1 and entry["label"] not in primary_labels:
              aliases.append(entry["label"])

          for target in (entry["fqdn"], entry["label"], f"{entry['label']}.{namespace}"):
              target_map[target].append(entry)

          for alias in aliases:
              key = alias.lower()
              owner = generated_owner.get(key)
              if owner is not None and owner != entry["ip"]:
                  fail(f"generated name {alias!r} maps to both {owner} and {entry['ip']}")
              generated_owner[key] = entry["ip"]
              add_unique(generated_by_ip[entry["ip"]], alias)

      manual_by_ip = collections.defaultdict(list)
      ssh_lines = []
      hosts = alias_config.get("hosts") or {}

      if secondary_running:
          for alias, details in sorted(hosts.items()):
              alias_key = alias.lower()
              if alias_key in primary_labels:
                  fail(f"manual alias {alias!r} collides with primary tailnet name")

              target = str(details["target"]).rstrip(".").lower()
              matches = target_map.get(target, [])
              if len(matches) == 0:
                  fail(f"manual alias {alias!r} targets unknown secondary host {details['target']!r}")
              if len(matches) > 1:
                  choices = ", ".join(sorted(match["fqdn"] for match in matches))
                  fail(f"manual alias {alias!r} target {details['target']!r} is ambiguous: {choices}")

              entry = matches[0]
              generated_ip = generated_owner.get(alias_key)
              if generated_ip is not None and generated_ip != entry["ip"]:
                  fail(f"manual alias {alias!r} collides with generated name for {generated_ip}")

              add_unique(manual_by_ip[entry["ip"]], alias)

              ssh_lines.append(f"Host {alias}")
              ssh_lines.append(f"  HostName {entry['ip']}")
              if details.get("user") is not None:
                  ssh_lines.append(f"  User {details['user']}")
              ssh_lines.append(f"  Port {details.get('port', 22)}")
              ssh_lines.append("  CheckHostIP no")
              for key, value in sorted((details.get("extraOptions") or {}).items()):
                  if isinstance(value, bool):
                      rendered = "yes" if value else "no"
                  else:
                      rendered = str(value)
                  ssh_lines.append(f"  {key} {rendered}")
              ssh_lines.append("")

      routes = sorted({entry["ip"] for entry in secondary_entries}, key=ipaddress.IPv4Address)

      with open(work / "routes.desired", "w", encoding="utf-8") as handle:
          for ip in routes:
              handle.write(f"{ip}\n")

      with open(work / "hosts.block", "w", encoding="utf-8") as handle:
          for ip in routes:
              names = []
              for name in generated_by_ip[ip] + manual_by_ip[ip]:
                  add_unique(names, name)
              if names:
                  handle.write(f"{ip}\t{' '.join(names)}\n")

      with open(work / "ssh_config", "w", encoding="utf-8") as handle:
          if ssh_lines:
              handle.write("\n".join(ssh_lines))
              handle.write("\n")

      ip_set = ", ".join(routes)
      nft_lines = [
          "table inet tail2_publish {",
          "  chain input {",
          "    type filter hook input priority -100; policy accept;",
          f"    iifname \"{tailscale_interface}\" ct state established,related counter accept",
          f"    iifname \"{tailscale_interface}\" counter drop",
          "  }",
          "",
          "  chain forward {",
          "    type filter hook forward priority -100; policy drop;",
          "    ct state established,related counter accept",
      ]
      if ip_set:
          nft_lines.append(
              f"    iifname \"{namespace_veth}\" oifname \"{tailscale_interface}\" ip daddr {{ {ip_set} }} counter accept"
          )
      nft_lines.extend(
          [
              "  }",
              "}",
              "",
              "table ip tail2_publish_nat {",
              "  chain postrouting {",
              "    type nat hook postrouting priority srcnat; policy accept;",
          ]
      )
      if secondary_self_ip:
          nft_lines.append(
              f"    ip saddr {veth_subnet} oifname \"{tailscale_interface}\" counter snat to {secondary_self_ip}"
          )
      nft_lines.extend(
          [
              "  }",
              "}",
          ]
      )
      with open(work / "tail2-publish.nft", "w", encoding="utf-8") as handle:
          handle.write("\n".join(nft_lines))
          handle.write("\n")
      PY

            log "applying root tailscale input exception"
            if ${pkgs.iptables}/bin/iptables -w -S ts-input >/dev/null 2>&1; then
              if ${pkgs.iptables}/bin/iptables -w -C ts-input -i ${cfg.hostVeth} -j RETURN >/dev/null 2>&1; then
                log "root tailscale input exception unchanged"
              else
                ${pkgs.iptables}/bin/iptables -w -I ts-input 1 -i ${cfg.hostVeth} -j RETURN
              fi
            fi

            log "applying namespace firewall"
            if [ -e "$nft_state" ] \
              && ${pkgs.diffutils}/bin/cmp -s "$work_dir/tail2-publish.nft" "$nft_state" \
              && ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft list table inet tail2_publish >/dev/null 2>&1 \
              && ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft list table ip tail2_publish_nat >/dev/null 2>&1; then
              log "namespace firewall unchanged"
            else
              log "replacing namespace firewall"
              ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft list table inet tail2_publish >/dev/null 2>&1 \
                && ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft delete table inet tail2_publish \
                || true
              ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft list table ip tail2_publish_nat >/dev/null 2>&1 \
                && ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft delete table ip tail2_publish_nat \
                || true
              ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft list table inet tail2_direct_access >/dev/null 2>&1 \
                && ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft delete table inet tail2_direct_access \
                || true
              ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft list table ip tail2_direct_access_nat >/dev/null 2>&1 \
                && ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft delete table ip tail2_direct_access_nat \
                || true
              ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} ${pkgs.nftables}/bin/nft -f "$work_dir/tail2-publish.nft"
              ${pkgs.coreutils}/bin/cp "$work_dir/tail2-publish.nft" "$nft_state"
              ${pkgs.coreutils}/bin/chmod 0644 "$nft_state"
            fi

            routes_present=true
            while IFS= read -r address; do
              [ -n "$address" ] || continue
              if ! ${pkgs.iproute2}/bin/ip route show "$address/32" \
                | ${pkgs.gnugrep}/bin/grep -Fq "via ${cfg.namespaceAddress} dev ${cfg.hostVeth}"; then
                routes_present=false
                break
              fi
            done <"$work_dir/routes.desired"

            if [ -e "$route_state" ] \
              && [ ! -e "$legacy_route_state" ] \
              && [ "$routes_present" = true ] \
              && ${pkgs.diffutils}/bin/cmp -s "$work_dir/routes.desired" "$route_state"; then
              log "direct routes unchanged"
            else
              log "installing direct routes"
              while IFS= read -r address; do
                [ -n "$address" ] || continue
                ${pkgs.iproute2}/bin/ip route replace "$address/32" via ${cfg.namespaceAddress} dev ${cfg.hostVeth} src ${cfg.hostAddress}
              done <"$work_dir/routes.desired"

              log "removing stale direct routes"
              for previous_state in "$route_state" "$legacy_route_state"; do
                [ -e "$previous_state" ] || continue
                while IFS= read -r old_address; do
                  old_address="''${old_address%/32}"
                  [ -n "$old_address" ] || continue
                  if ! ${pkgs.gnugrep}/bin/grep -Fxq "$old_address" "$work_dir/routes.desired"; then
                    ${pkgs.iproute2}/bin/ip route del "$old_address/32" via ${cfg.namespaceAddress} dev ${cfg.hostVeth} >/dev/null 2>&1 \
                      || ${pkgs.iproute2}/bin/ip route del "$old_address/32" dev ${cfg.hostVeth} >/dev/null 2>&1 \
                      || true
                  fi
                done <"$previous_state"
              done

              ${pkgs.coreutils}/bin/cp "$work_dir/routes.desired" "$route_state"
              ${pkgs.coreutils}/bin/chmod 0644 "$route_state"
              ${pkgs.coreutils}/bin/rm -f "$legacy_route_state"
            fi

            log "updating hosts file"
            hosts_target="$hosts_file"
            if [ -L "$hosts_target" ]; then
              hosts_link_target="$(${pkgs.coreutils}/bin/readlink "$hosts_target")"
              case "$hosts_link_target" in
                /.host-etc/*)
                  hosts_target="$hosts_link_target"
                  ;;
              esac
            fi
            hosts_dir="$(${pkgs.coreutils}/bin/dirname "$hosts_target")"
            hosts_candidate="$work_dir/hosts"
            if [ -e "$hosts_target" ]; then
              ${pkgs.gawk}/bin/awk \
                -v begin="# BEGIN ${cfg.namespace} published access" \
                -v end="# END ${cfg.namespace} published access" \
                -v legacy_begin="# BEGIN ${cfg.namespace} direct access" \
                -v legacy_end="# END ${cfg.namespace} direct access" '
                   $0 == begin || $0 == legacy_begin { skip = 1; pending_blank = 0; next }
                   $0 == end || $0 == legacy_end { skip = 0; next }
                   skip { next }
                   $0 == "" { pending_blank++; next }
                   {
                     while (pending_blank > 0) {
                       print ""
                       pending_blank--
                     }
                     print
                   }
                 ' "$hosts_target" >"$hosts_candidate"
            else
              : >"$hosts_candidate"
            fi
            if [ -s "$work_dir/hosts.block" ]; then
              {
                if [ -s "$hosts_candidate" ]; then
                  printf '\n'
                fi
                printf '# BEGIN ${cfg.namespace} published access\n'
                ${pkgs.coreutils}/bin/cat "$work_dir/hosts.block"
                printf '# END ${cfg.namespace} published access\n'
              } >>"$hosts_candidate"
            fi
            if [ -e "$hosts_target" ] && ${pkgs.diffutils}/bin/cmp -s "$hosts_candidate" "$hosts_target"; then
              log "hosts file unchanged"
            else
              log "replacing hosts file"
              tmp_hosts="$(${pkgs.coreutils}/bin/mktemp "$hosts_dir/hosts.${cfg.namespace}.XXXXXX")"
              ${pkgs.coreutils}/bin/cp "$hosts_candidate" "$tmp_hosts"
              ${pkgs.coreutils}/bin/chown root:root "$tmp_hosts"
              ${pkgs.coreutils}/bin/chmod 0644 "$tmp_hosts"
              ${pkgs.coreutils}/bin/mv "$tmp_hosts" "$hosts_target"
              tmp_hosts=""
            fi

            if [ -e "$ssh_config" ] && ${pkgs.diffutils}/bin/cmp -s "$work_dir/ssh_config" "$ssh_config"; then
              log "ssh aliases unchanged"
            else
              log "updating ssh aliases"
              tmp_ssh="$ssh_config.tmp.$$"
              ${pkgs.coreutils}/bin/cp "$work_dir/ssh_config" "$tmp_ssh"
              ${pkgs.coreutils}/bin/chown ${lib.escapeShellArg cfg.sshConfigUser}:${lib.escapeShellArg cfg.sshConfigGroup} "$tmp_ssh"
              ${pkgs.coreutils}/bin/chmod 0644 "$tmp_ssh"
              ${pkgs.coreutils}/bin/mv "$tmp_ssh" "$ssh_config"
              tmp_ssh=""
            fi

            log "done"
    '';
  in {
    options.features.multi-tailnet = {
      enable = lib.mkEnableOption "a second Tailscale tailnet in a network namespace";

      runtimeConfigFile = lib.mkOption {
        type = lib.types.path;
        description = "Runtime JSON config file containing secondary tailnet aliases.";
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

      sshConfigUser = lib.mkOption {
        type = lib.types.str;
        default = "tarttelin";
        description = "Local user that owns the generated SSH alias include file.";
      };

      sshConfigGroup = lib.mkOption {
        type = lib.types.str;
        default = "users";
        description = "Local group that owns the generated SSH alias include file.";
      };
    };

    config = lib.mkIf cfg.enable {
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

      environment.systemPackages = [
        tail2
        tail2Publish
        validateRuntimeConfig
      ];

      networking = {
        # The early tail2_root_guard table remains the isolation boundary. Trusting
        # the veth here only prevents the stock NixOS firewall from dropping
        # replies that tail2_root_guard has already allowed.
        firewall.trustedInterfaces = [cfg.hostVeth];

        firewall.extraForwardRules = ''
          iifname "${cfg.hostVeth}" oifname "${cfg.tailscaleInterface}" drop
          iifname "${cfg.hostVeth}" oifname != "${cfg.hostVeth}" accept
          oifname "${cfg.hostVeth}" ct state established,related accept
        '';

        nftables.tables."tail2-root-guard" = {
          family = "inet";
          name = "tail2_root_guard";
          content = ''
            chain input {
              type filter hook input priority -100; policy accept;
              iifname "${cfg.hostVeth}" ct state established,related counter accept
              iifname "${cfg.hostVeth}" drop
            }

            chain forward {
              type filter hook forward priority -100; policy accept;
              iifname "${cfg.hostVeth}" oifname "${cfg.tailscaleInterface}" drop
            }
          '';
        };

        nftables.tables."tail2-nat" = {
          family = "ip";
          name = "tail2_nat";
          content = ''
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              ip saddr ${cfg.vethSubnet} oifname != "${cfg.hostVeth}" oifname != "${cfg.tailscaleInterface}" masquerade
            }
          '';
        };
      };

      programs.ssh.extraConfig = ''
        Include ${sshConfigPath}
      '';

      environment.etc.hosts.mode = "0644";

      system.activationScripts."${cfg.namespace}-state-backup" = {
        deps = [];
        text = ''
          backup_root=/var/lib/multi-tailnet-backup/initial
          if [ ! -e "$backup_root" ]; then
            ${pkgs.coreutils}/bin/mkdir -p "$backup_root"
            if [ -e /var/lib/tailscale ]; then
              ${pkgs.coreutils}/bin/cp -a /var/lib/tailscale "$backup_root/tailscale"
            fi
            if [ -e ${lib.escapeShellArg cfg.stateDir} ]; then
              ${pkgs.coreutils}/bin/cp -a ${lib.escapeShellArg cfg.stateDir} "$backup_root/${baseNameOf cfg.stateDir}"
            fi
          fi
        '';
      };

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
          "f ${routeStatePath} 0644 root root -"
          "f ${nftStatePath} 0644 root root -"
          "d ${sshConfigDir} 0755 ${cfg.sshConfigUser} ${cfg.sshConfigGroup} -"
          "f ${sshConfigPath} 0644 ${cfg.sshConfigUser} ${cfg.sshConfigGroup} -"
          "z ${sshConfigPath} 0644 ${cfg.sshConfigUser} ${cfg.sshConfigGroup} -"
          "d ${cfg.stateDir} 0700 root root -"
        ];

        timers."${cfg.namespace}-publish" = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "15s";
            OnUnitActiveSec = "300s";
            Unit = "${cfg.namespace}-publish.service";
          };
        };

        services = {
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

          "${cfg.namespace}-publish" = {
            description = "Publish additive access for ${cfg.namespace} Tailscale";
            wantedBy = ["multi-user.target"];
            after = [
              "agenix.service"
              "tailscaled.service"
              "${cfg.namespace}-netns.service"
              "tailscaled-${cfg.namespace}.service"
            ];
            requires = ["${cfg.namespace}-netns.service"];
            wants = [
              "agenix.service"
              "tailscaled.service"
              "tailscaled-${cfg.namespace}.service"
            ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${tail2Publish}/bin/${cfg.namespace}-publish";
            };
          };
        };
      };
    };
  };
}
