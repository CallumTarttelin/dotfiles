{pkgs}:
pkgs.writeShellApplication {
  name = "localproxy";
  runtimeInputs = with pkgs; [
    coreutils
    gawk
    gnused
    haproxy
    socat
  ];
  text = ''
    set -euo pipefail

    bind_addr="''${LOCALPROXY_BIND:-127.0.0.1}"
    state_root="''${XDG_STATE_HOME:-$HOME/.local/state}/localproxy"

    default_max_total_conns="''${LOCALPROXY_DEFAULT_MAX_TOTAL_CONNS:-1000}"
    default_max_sessions_per_second="''${LOCALPROXY_DEFAULT_MAX_SESSIONS_PER_SECOND:-0}"

    default_http_max_backend_conns="''${LOCALPROXY_HTTP_DEFAULT_MAX_BACKEND_CONNS:-32}"
    default_http_max_idle_backend_conns="''${LOCALPROXY_HTTP_DEFAULT_MAX_IDLE_BACKEND_CONNS:-8}"
    default_http_queue_timeout="''${LOCALPROXY_HTTP_DEFAULT_QUEUE_TIMEOUT:-2s}"
    default_http_keepalive_timeout="''${LOCALPROXY_HTTP_DEFAULT_HTTP_KEEPALIVE_TIMEOUT:-15s}"
    default_http_tunnel_timeout="''${LOCALPROXY_HTTP_DEFAULT_TUNNEL_TIMEOUT:-1h}"

    usage() {
      cat >&2 <<'USAGE'
    usage:
      localproxy <host> enable [--max-total-conns N] [--max-sessions-per-second N] <port> [port...]
      localproxy <host> disable
      localproxy <host> status
      localproxy status

      localproxy http <host> enable [--max-backend-conns N] [--max-idle-backend-conns N] [--queue-timeout DURATION] [--http-keepalive-timeout DURATION] [--tunnel-timeout DURATION] <port> [port...]
      localproxy http <host> disable
      localproxy http <host> status
      localproxy http status

    Examples:
      localproxy devbox enable --max-total-conns 1000 --max-sessions-per-second 20 5173 3000 9000
      localproxy http devbox enable --max-backend-conns 32 --max-idle-backend-conns 8 5173
      localproxy devbox disable
      localproxy http devbox disable
    USAGE
    }

    die() {
      printf 'localproxy: %s\n' "$*" >&2
      exit 1
    }

    usage_error() {
      printf 'localproxy: %s\n' "$*" >&2
      exit 64
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

    validate_nonnegative_integer() {
      local value="$1"
      local label="$2"
      [[ "$value" =~ ^[0-9]+$ ]] || usage_error "invalid $label: $value"
    }

    validate_positive_integer() {
      local value="$1"
      local label="$2"
      validate_nonnegative_integer "$value" "$label"
      ((value >= 1)) || usage_error "invalid $label: $value"
    }

    validate_duration() {
      local value="$1"
      local label="$2"
      [[ -n "$value" ]] || usage_error "invalid $label: $value"
      [[ "$value" =~ ^[0-9]+(ms|s|m|h|d)?$ ]] || usage_error "invalid $label: $value"
    }

    mode_root() {
      local mode="$1"
      case "$mode" in
        tcp)
          printf '%s\n' "$state_root"
          ;;
        http)
          printf '%s/http\n' "$state_root"
          ;;
        *)
          die "unsupported mode: $mode"
          ;;
      esac
    }

    host_dir() {
      local mode="$1"
      local host="$2"
      printf '%s/%s\n' "$(mode_root "$mode")" "$host"
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

    metadata_value() {
      local config="$1"
      local key="$2"
      [[ -f "$config" ]] || return 0
      sed -n "s/^# localproxy-$key: //p" "$config" | head -n1
    }

    socket_info() {
      local socket="$1"
      [[ -S "$socket" ]] || return 1
      printf 'show info\n' | socat -T1 - UNIX-CONNECT:"$socket" 2>/dev/null
    }

    socket_stat_csv() {
      local socket="$1"
      [[ -S "$socket" ]] || return 1
      printf 'show stat\n' | socat -T1 - UNIX-CONNECT:"$socket" 2>/dev/null
    }

    render_tcp_config() {
      local host="$1"
      local config="$2"
      local dir="$3"
      local max_total_conns="$4"
      local max_sessions_per_second="$5"
      shift 5

      local safe_host
      safe_host="$(safe_name "$host")"
      local socket
      socket="$dir/haproxy.sock"

      {
        cat <<CFG
    # localproxy-mode: tcp
    # localproxy-host: ''${host}
    # localproxy-ports: $*
    # localproxy-max-total-conns: ''${max_total_conns}
    # localproxy-max-sessions-per-second: ''${max_sessions_per_second}
    global
      daemon
      maxconn ''${max_total_conns}
      stats socket ''${socket} mode 600 level operator

    defaults
      mode tcp
      option tcpka
      timeout connect 5s
      timeout client 1h
      timeout server 1h

    frontend localproxy_''${safe_host}
      maxconn ''${max_total_conns}
    CFG

        if ((max_sessions_per_second > 0)); then
          cat <<CFG
      rate-limit sessions ''${max_sessions_per_second}
    CFG
        fi

        local port
        for port in "$@"; do
          cat <<CFG
      bind ''${bind_addr}:''${port} backlog 64
      use_backend localproxy_''${safe_host}_''${port}_backend if { dst_port ''${port} }
    CFG
        done

        for port in "$@"; do
          cat <<CFG
    backend localproxy_''${safe_host}_''${port}_backend
      server target ''${host}:''${port} maxconn ''${max_total_conns}
    CFG
        done
      } >"$config"
    }

    render_http_config() {
      local host="$1"
      local config="$2"
      local dir="$3"
      local max_backend_conns="$4"
      local max_idle_backend_conns="$5"
      local queue_timeout="$6"
      local http_keepalive_timeout="$7"
      local tunnel_timeout="$8"
      shift 8

      local safe_host
      safe_host="$(safe_name "$host")"
      local socket
      socket="$dir/haproxy.sock"

      {
        cat <<CFG
    # localproxy-mode: http
    # localproxy-host: ''${host}
    # localproxy-ports: $*
    # localproxy-max-backend-conns: ''${max_backend_conns}
    # localproxy-max-idle-backend-conns: ''${max_idle_backend_conns}
    # localproxy-queue-timeout: ''${queue_timeout}
    # localproxy-http-keepalive-timeout: ''${http_keepalive_timeout}
    # localproxy-tunnel-timeout: ''${tunnel_timeout}
    global
      daemon
      stats socket ''${socket} mode 600 level operator

    defaults
      mode http
      option http-keep-alive
      timeout connect 5s
      timeout client 1h
      timeout server 1h
      timeout http-request 5s
      timeout http-keep-alive ''${http_keepalive_timeout}
      timeout queue ''${queue_timeout}
      timeout tunnel ''${tunnel_timeout}
    CFG

        local port
        for port in "$@"; do
          cat <<CFG

    frontend localproxy_http_''${safe_host}_''${port}
      bind ''${bind_addr}:''${port}
      default_backend localproxy_http_''${safe_host}_''${port}_backend

    backend localproxy_http_''${safe_host}_''${port}_backend
      http-reuse safe
      server target ''${host}:''${port} maxconn ''${max_backend_conns} pool-max-conn ''${max_idle_backend_conns} pool-purge-delay 30s
    CFG
        done
      } >"$config"
    }

    launch_proxy() {
      local config="$1"
      local pidfile="$2"
      local oldpid

      if pid_is_alive "$pidfile"; then
        oldpid="$(cat "$pidfile")"
        haproxy -f "$config" -D -p "$pidfile" -sf "$oldpid"
      else
        rm -f "$pidfile"
        haproxy -f "$config" -D -p "$pidfile"
      fi
    }

    enable_tcp_proxy() {
      local host="$1"
      shift

      validate_host "$host"

      local max_total_conns="$default_max_total_conns"
      local max_sessions_per_second="$default_max_sessions_per_second"
      validate_positive_integer "$max_total_conns" "LOCALPROXY_DEFAULT_MAX_TOTAL_CONNS"
      validate_nonnegative_integer "$max_sessions_per_second" "LOCALPROXY_DEFAULT_MAX_SESSIONS_PER_SECOND"

      while (($# > 0)); do
        case "$1" in
          --max-total-conns)
            (($# >= 2)) || usage_error "missing value for --max-total-conns"
            validate_positive_integer "$2" "--max-total-conns"
            max_total_conns="$2"
            shift 2
            ;;
          --max-sessions-per-second)
            (($# >= 2)) || usage_error "missing value for --max-sessions-per-second"
            validate_nonnegative_integer "$2" "--max-sessions-per-second"
            max_sessions_per_second="$2"
            shift 2
            ;;
          --)
            shift
            break
            ;;
          -*)
            usage_error "unknown option: $1"
            ;;
          *)
            break
            ;;
        esac
      done

      (($# > 0)) || usage_error "enable needs at least one port"

      local ports=()
      local port
      for port in "$@"; do
        validate_port "$port"
        ports+=("$port")
      done

      local dir config pidfile
      dir="$(host_dir tcp "$host")"
      config="$dir/haproxy.cfg"
      pidfile="$dir/haproxy.pid"

      mkdir -p "$dir"
      render_tcp_config "$host" "$config" "$dir" "$max_total_conns" "$max_sessions_per_second" "''${ports[@]}"
      haproxy -c -f "$config" >/dev/null
      launch_proxy "$config" "$pidfile"

      printf 'enabled %s on %s -> %s for port(s): %s, max-total-conns: %s, max-sessions-per-second: %s\n' \
        "$host" "$bind_addr" "$host" "''${ports[*]}" "$max_total_conns" "$max_sessions_per_second"
    }

    enable_http_proxy() {
      local host="$1"
      shift

      validate_host "$host"

      local max_backend_conns="$default_http_max_backend_conns"
      local max_idle_backend_conns="$default_http_max_idle_backend_conns"
      local queue_timeout="$default_http_queue_timeout"
      local http_keepalive_timeout="$default_http_keepalive_timeout"
      local tunnel_timeout="$default_http_tunnel_timeout"

      validate_positive_integer "$max_backend_conns" "LOCALPROXY_HTTP_DEFAULT_MAX_BACKEND_CONNS"
      validate_nonnegative_integer "$max_idle_backend_conns" "LOCALPROXY_HTTP_DEFAULT_MAX_IDLE_BACKEND_CONNS"
      validate_duration "$queue_timeout" "LOCALPROXY_HTTP_DEFAULT_QUEUE_TIMEOUT"
      validate_duration "$http_keepalive_timeout" "LOCALPROXY_HTTP_DEFAULT_HTTP_KEEPALIVE_TIMEOUT"
      validate_duration "$tunnel_timeout" "LOCALPROXY_HTTP_DEFAULT_TUNNEL_TIMEOUT"

      while (($# > 0)); do
        case "$1" in
          --max-backend-conns)
            (($# >= 2)) || usage_error "missing value for --max-backend-conns"
            validate_positive_integer "$2" "--max-backend-conns"
            max_backend_conns="$2"
            shift 2
            ;;
          --max-idle-backend-conns)
            (($# >= 2)) || usage_error "missing value for --max-idle-backend-conns"
            validate_nonnegative_integer "$2" "--max-idle-backend-conns"
            max_idle_backend_conns="$2"
            shift 2
            ;;
          --queue-timeout)
            (($# >= 2)) || usage_error "missing value for --queue-timeout"
            validate_duration "$2" "--queue-timeout"
            queue_timeout="$2"
            shift 2
            ;;
          --http-keepalive-timeout)
            (($# >= 2)) || usage_error "missing value for --http-keepalive-timeout"
            validate_duration "$2" "--http-keepalive-timeout"
            http_keepalive_timeout="$2"
            shift 2
            ;;
          --tunnel-timeout)
            (($# >= 2)) || usage_error "missing value for --tunnel-timeout"
            validate_duration "$2" "--tunnel-timeout"
            tunnel_timeout="$2"
            shift 2
            ;;
          --)
            shift
            break
            ;;
          -*)
            usage_error "unknown option: $1"
            ;;
          *)
            break
            ;;
        esac
      done

      (($# > 0)) || usage_error "enable needs at least one port"

      local ports=()
      local port
      for port in "$@"; do
        validate_port "$port"
        ports+=("$port")
      done

      local dir config pidfile
      dir="$(host_dir http "$host")"
      config="$dir/haproxy.cfg"
      pidfile="$dir/haproxy.pid"

      mkdir -p "$dir"
      render_http_config "$host" "$config" "$dir" "$max_backend_conns" "$max_idle_backend_conns" "$queue_timeout" "$http_keepalive_timeout" "$tunnel_timeout" "''${ports[@]}"
      haproxy -c -f "$config" >/dev/null
      launch_proxy "$config" "$pidfile"

      printf 'enabled http %s on %s -> %s for port(s): %s, max-backend-conns: %s, max-idle-backend-conns: %s, queue-timeout: %s, http-keepalive-timeout: %s, tunnel-timeout: %s\n' \
        "$host" "$bind_addr" "$host" "''${ports[*]}" "$max_backend_conns" "$max_idle_backend_conns" "$queue_timeout" "$http_keepalive_timeout" "$tunnel_timeout"
    }

    disable_proxy() {
      local mode="$1"
      local host="$2"
      validate_host "$host"

      local dir pidfile pid
      dir="$(host_dir "$mode" "$host")"
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
      if [[ "$mode" == http ]]; then
        printf 'disabled http %s\n' "$host"
      else
        printf 'disabled %s\n' "$host"
      fi
    }

    tcp_status_one() {
      local host="$1"
      validate_host "$host"

      local dir config pidfile socket state ports max_total_conns max_sessions_per_second live_stats curr_conns conn_rate cum_conns details live_details
      dir="$(host_dir tcp "$host")"
      config="$dir/haproxy.cfg"
      pidfile="$dir/haproxy.pid"
      socket="$dir/haproxy.sock"

      if pid_is_alive "$pidfile"; then
        state="running pid $(cat "$pidfile")"
      elif [[ -e "$dir" ]]; then
        state="stopped"
      else
        state="not configured"
      fi

      ports="$(metadata_value "$config" "ports")"
      if [[ -z "''${ports:-}" ]]; then
        ports="$(
          if [[ -f "$config" ]]; then
            sed -n 's/^  bind [^:]*:\([0-9]\+\).*$/\1/p' "$config" | paste -sd ' ' -
          fi
        )"
      fi
      max_total_conns="$(metadata_value "$config" "max-total-conns")"
      max_sessions_per_second="$(metadata_value "$config" "max-sessions-per-second")"

      details=""
      if [[ -n "''${ports:-}" ]]; then
        details="ports: $ports"
      fi
      if [[ -n "''${max_total_conns:-}" ]]; then
        if [[ -n "$details" ]]; then
          details="$details,"
        fi
        details="$details max-total-conns: $max_total_conns"
      fi
      if [[ -n "''${max_sessions_per_second:-}" ]]; then
        if [[ -n "$details" ]]; then
          details="$details,"
        fi
        details="$details max-sessions-per-second: $max_sessions_per_second"
      fi

      live_details=""
      if [[ "$state" == running* ]]; then
        live_stats="$(socket_info "$socket" || true)"
        if [[ -n "$live_stats" ]]; then
          curr_conns="$(printf '%s\n' "$live_stats" | sed -n 's/^CurrConns: *//p' | head -n1)"
          conn_rate="$(printf '%s\n' "$live_stats" | sed -n 's/^ConnRate: *//p' | head -n1)"
          cum_conns="$(printf '%s\n' "$live_stats" | sed -n 's/^CumConns: *//p' | head -n1)"

          if [[ -n "''${curr_conns:-}" ]]; then
            live_details="CurrConns: $curr_conns"
          fi
          if [[ -n "''${conn_rate:-}" ]]; then
            if [[ -n "$live_details" ]]; then
              live_details="$live_details,"
            fi
            live_details="$live_details ConnRate: $conn_rate"
          fi
          if [[ -n "''${cum_conns:-}" ]]; then
            if [[ -n "$live_details" ]]; then
              live_details="$live_details,"
            fi
            live_details="$live_details CumConns: $cum_conns"
          fi
        fi
      fi

      if [[ -n "$details" ]]; then
        if [[ -n "$live_details" ]]; then
          printf '%s: %s, %s, %s\n' "$host" "$state" "$details" "$live_details"
        else
          printf '%s: %s, %s\n' "$host" "$state" "$details"
        fi
      else
        printf '%s: %s\n' "$host" "$state"
      fi
    }

    http_port_stat_summary() {
      local csv_stats="$1"
      local host="$2"
      local port="$3"
      local safe_host
      safe_host="$(safe_name "$host")"
      local frontend="localproxy_http_''${safe_host}_''${port}"
      local backend="localproxy_http_''${safe_host}_''${port}_backend"

      printf '%s\n' "$csv_stats" | awk -F, -v frontend="$frontend" -v backend="$backend" '
        NR == 1 {
          for (i = 1; i <= NF; i++) {
            name = $i
            sub(/^# */, "", name)
            idx[name] = i
          }
          next
        }
        $1 == frontend && $2 == "FRONTEND" {
          if ("req_tot" in idx) req_front = $(idx["req_tot"])
          if ("stot" in idx) conn_front = $(idx["stot"])
        }
        $1 == backend && $2 == "BACKEND" {
          if ("qcur" in idx) qcur = $(idx["qcur"])
          if ("req_tot" in idx) req_back = $(idx["req_tot"])
        }
        $1 == backend && $2 == "target" {
          if ("scur" in idx) scur = $(idx["scur"])
          if ("stot" in idx) conn_back = $(idx["stot"])
        }
        END {
          req_tot = req_back != "" ? req_back : req_front
          conn_tot = conn_back != "" ? conn_back : conn_front
          printf "qcur=%s scur=%s cumreq=%s cumconn=%s", qcur, scur, req_tot, conn_tot
        }
      '
    }

    http_status_one() {
      local host="$1"
      validate_host "$host"

      local dir config pidfile socket state ports max_backend_conns max_idle_backend_conns queue_timeout http_keepalive_timeout tunnel_timeout details live_details csv_stats port summary
      dir="$(host_dir http "$host")"
      config="$dir/haproxy.cfg"
      pidfile="$dir/haproxy.pid"
      socket="$dir/haproxy.sock"

      if pid_is_alive "$pidfile"; then
        state="running pid $(cat "$pidfile")"
      elif [[ -e "$dir" ]]; then
        state="stopped"
      else
        state="not configured"
      fi

      ports="$(metadata_value "$config" "ports")"
      max_backend_conns="$(metadata_value "$config" "max-backend-conns")"
      max_idle_backend_conns="$(metadata_value "$config" "max-idle-backend-conns")"
      queue_timeout="$(metadata_value "$config" "queue-timeout")"
      http_keepalive_timeout="$(metadata_value "$config" "http-keepalive-timeout")"
      tunnel_timeout="$(metadata_value "$config" "tunnel-timeout")"

      details="mode: http"
      if [[ -n "''${ports:-}" ]]; then
        details="$details, ports: $ports"
      fi
      if [[ -n "''${max_backend_conns:-}" ]]; then
        details="$details, max-backend-conns: $max_backend_conns"
      fi
      if [[ -n "''${max_idle_backend_conns:-}" ]]; then
        details="$details, max-idle-backend-conns: $max_idle_backend_conns"
      fi
      if [[ -n "''${queue_timeout:-}" ]]; then
        details="$details, queue-timeout: $queue_timeout"
      fi
      if [[ -n "''${http_keepalive_timeout:-}" ]]; then
        details="$details, http-keepalive-timeout: $http_keepalive_timeout"
      fi
      if [[ -n "''${tunnel_timeout:-}" ]]; then
        details="$details, tunnel-timeout: $tunnel_timeout"
      fi

      live_details=""
      if [[ "$state" == running* ]]; then
        csv_stats="$(socket_stat_csv "$socket" || true)"
        if [[ -n "$csv_stats" && -n "''${ports:-}" ]]; then
          for port in $ports; do
            summary="$(http_port_stat_summary "$csv_stats" "$host" "$port")"
            if [[ -n "$summary" ]]; then
              if [[ -n "$live_details" ]]; then
                live_details="$live_details, "
              fi
              live_details="$live_details''${port}[$summary]"
            fi
          done
        fi
      fi

      if [[ -n "$live_details" ]]; then
        printf '%s: %s, %s, port-stats: %s\n' "$host" "$state" "$details" "$live_details"
      else
        printf '%s: %s, %s\n' "$host" "$state" "$details"
      fi
    }

    status_one() {
      local mode="$1"
      local host="$2"
      case "$mode" in
        tcp)
          tcp_status_one "$host"
          ;;
        http)
          http_status_one "$host"
          ;;
        *)
          die "unsupported mode: $mode"
          ;;
      esac
    }

    status_all() {
      local mode="$1"
      local root any dir host
      root="$(mode_root "$mode")"

      if [[ ! -d "$root" ]]; then
        if [[ "$mode" == http ]]; then
          printf 'no local http proxies configured\n'
        else
          printf 'no local proxies configured\n'
        fi
        return
      fi

      any=0
      for dir in "$root"/*; do
        [[ -d "$dir" ]] || continue
        [[ -f "$dir/haproxy.cfg" || -f "$dir/haproxy.pid" ]] || continue
        any=1
        host="$(basename "$dir")"
        status_one "$mode" "$host"
      done

      if ((any == 0)); then
        if [[ "$mode" == http ]]; then
          printf 'no local http proxies configured\n'
        else
          printf 'no local proxies configured\n'
        fi
      fi
    }

    if (($# == 1)) && [[ "$1" == "status" ]]; then
      status_all tcp
      exit 0
    fi

    if (($# == 2)) && [[ "$1" == "http" && "$2" == "status" ]]; then
      status_all http
      exit 0
    fi

    mode="tcp"
    if (($# >= 1)) && [[ "$1" == "http" ]]; then
      mode="http"
      (($# >= 3)) || {
        usage
        exit 64
      }
      host="$2"
      action="$3"
      shift 3
    else
      (($# >= 2)) || {
        usage
        exit 64
      }
      host="$1"
      action="$2"
      shift 2
    fi

    case "$action" in
      enable)
        if [[ "$mode" == http ]]; then
          enable_http_proxy "$host" "$@"
        else
          enable_tcp_proxy "$host" "$@"
        fi
        ;;
      disable)
        (($# == 0)) || usage_error "disable does not accept ports"
        disable_proxy "$mode" "$host"
        ;;
      status)
        (($# == 0)) || usage_error "status does not accept ports"
        status_one "$mode" "$host"
        ;;
      *)
        usage
        exit 64
        ;;
    esac
  '';
}
