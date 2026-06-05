{pkgs}:
pkgs.writeShellApplication {
  name = "localproxy";
  runtimeInputs = with pkgs; [
    coreutils
    gnused
    haproxy
  ];
  text = ''
    set -euo pipefail

    bind_addr="''${LOCALPROXY_BIND:-127.0.0.1}"
    state_root="''${XDG_STATE_HOME:-$HOME/.local/state}/localproxy"

    usage() {
      cat >&2 <<'USAGE'
    usage:
      localproxy <host> enable <port> [port...]
      localproxy <host> disable
      localproxy <host> status
      localproxy status

    Examples:
      localproxy devbox enable 5173 3000 9000
      localproxy devbox disable
    USAGE
    }

    die() {
      printf 'localproxy: %s\n' "$*" >&2
      exit 1
    }

    validate_host() {
      local host="$1"
      [[ "$host" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid host: $host"
    }

    validate_port() {
      local port="$1"
      [[ "$port" =~ ^[0-9]+$ ]] || die "invalid port: $port"
      ((port >= 1 && port <= 65535)) || die "invalid port: $port"
    }

    host_dir() {
      printf '%s/%s\n' "$state_root" "$1"
    }

    safe_name() {
      printf '%s\n' "$1" | sed 's/[^A-Za-z0-9_]/_/g'
    }

    pid_is_alive() {
      local pidfile="$1"
      [[ -s "$pidfile" ]] || return 1
      local pid
      pid="$(cat "$pidfile")"
      [[ "$pid" =~ ^[0-9]+$ ]] || return 1
      kill -0 "$pid" >/dev/null 2>&1
    }

    render_config() {
      local host="$1"
      local config="$2"
      shift 2

      local safe_host
      safe_host="$(safe_name "$host")"

      {
        cat <<CFG
    global
      daemon
      maxconn 20000

    defaults
      mode tcp
      option tcpka
      timeout connect 5s
      timeout client 1h
      timeout server 1h
    CFG

        local port
        for port in "$@"; do
          cat <<CFG

    frontend localproxy_''${safe_host}_''${port}
      bind ''${bind_addr}:''${port}
      default_backend localproxy_''${safe_host}_''${port}_backend

    backend localproxy_''${safe_host}_''${port}_backend
      server target ''${host}:''${port}
    CFG
        done
      } >"$config"
    }

    enable_proxy() {
      local host="$1"
      shift
      (($# > 0)) || die "enable needs at least one port"

      validate_host "$host"

      local port
      for port in "$@"; do
        validate_port "$port"
      done

      local dir config pidfile oldpid
      dir="$(host_dir "$host")"
      config="$dir/haproxy.cfg"
      pidfile="$dir/haproxy.pid"

      mkdir -p "$dir"
      render_config "$host" "$config" "$@"
      haproxy -c -f "$config" >/dev/null

      if pid_is_alive "$pidfile"; then
        oldpid="$(cat "$pidfile")"
        haproxy -f "$config" -D -p "$pidfile" -sf "$oldpid"
      else
        rm -f "$pidfile"
        haproxy -f "$config" -D -p "$pidfile"
      fi

      printf 'enabled %s on %s -> %s for port(s): %s\n' "$host" "$bind_addr" "$host" "$*"
    }

    disable_proxy() {
      local host="$1"
      validate_host "$host"

      local dir pidfile pid
      dir="$(host_dir "$host")"
      pidfile="$dir/haproxy.pid"

      if pid_is_alive "$pidfile"; then
        pid="$(cat "$pidfile")"
        kill "$pid" >/dev/null 2>&1 || true
        for _ in {1..50}; do
          kill -0 "$pid" >/dev/null 2>&1 || break
          sleep 0.1
        done
      fi

      rm -rf "$dir"
      printf 'disabled %s\n' "$host"
    }

    status_one() {
      local host="$1"
      validate_host "$host"

      local dir config pidfile state ports
      dir="$(host_dir "$host")"
      config="$dir/haproxy.cfg"
      pidfile="$dir/haproxy.pid"

      if pid_is_alive "$pidfile"; then
        state="running pid $(cat "$pidfile")"
      elif [[ -e "$dir" ]]; then
        state="stopped"
      else
        state="not configured"
      fi

      ports="$(
        if [[ -f "$config" ]]; then
          sed -n 's/^  bind [^:]*:\([0-9]\+\)$/\1/p' "$config" | paste -sd ' ' -
        fi
      )"

      if [[ -n "''${ports:-}" ]]; then
        printf '%s: %s, ports: %s\n' "$host" "$state" "$ports"
      else
        printf '%s: %s\n' "$host" "$state"
      fi
    }

    status_all() {
      if [[ ! -d "$state_root" ]]; then
        printf 'no local proxies configured\n'
        return
      fi

      local any=0 dir host
      for dir in "$state_root"/*; do
        [[ -d "$dir" ]] || continue
        any=1
        host="$(basename "$dir")"
        status_one "$host"
      done

      ((any == 1)) || printf 'no local proxies configured\n'
    }

    if (($# == 1)) && [[ "$1" == "status" ]]; then
      status_all
      exit 0
    fi

    (($# >= 2)) || {
      usage
      exit 64
    }

    host="$1"
    action="$2"
    shift 2

    case "$action" in
      enable)
        enable_proxy "$host" "$@"
        ;;
      disable)
        (($# == 0)) || die "disable does not accept ports"
        disable_proxy "$host"
        ;;
      status)
        (($# == 0)) || die "status does not accept ports"
        status_one "$host"
        ;;
      *)
        usage
        exit 64
        ;;
    esac
  '';
}
