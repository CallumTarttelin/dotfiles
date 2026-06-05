package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const (
	defaultMaxTotalConns        = 1000
	defaultMaxSessionsPerSecond = 0
	defaultMaxBackendConns      = 32
	defaultMaxIdleBackendConns  = 8
	defaultQueueTimeout         = "2s"
	defaultKeepAliveTimeout     = "15s"
	defaultTunnelTimeout        = "1h"
	defaultHTTP3Policy          = "auto"
	defaultFrontendALPN         = "h2,http/1.1"
)

type Limits struct {
	MaxTotalConns        int    `json:"max_total_conns"`
	MaxSessionsPerSecond int    `json:"max_sessions_per_second"`
	MaxBackendConns      int    `json:"max_backend_conns"`
	MaxIdleBackendConns  int    `json:"max_idle_backend_conns"`
	QueueTimeout         string `json:"queue_timeout"`
	HTTPKeepAliveTimeout string `json:"http_keepalive_timeout"`
	TunnelTimeout        string `json:"tunnel_timeout"`
}

type Config struct {
	Host           string     `json:"host"`
	BindAddr       string     `json:"bind_addr"`
	StateDir       string     `json:"state_dir"`
	FrontendCert   string     `json:"frontend_cert,omitempty"`
	HTTP3Policy    string     `json:"http3_policy"`
	HTTP3Effective bool       `json:"http3_effective"`
	FrontendALPN   string     `json:"frontend_alpn"`
	Ports          []PortSpec `json:"ports"`
	Limits         Limits     `json:"limits"`
}

func defaultLimits() (Limits, error) {
	maxTotal, err := envPositiveInt("LOCALPROXY_DEFAULT_MAX_TOTAL_CONNS", defaultMaxTotalConns)
	if err != nil {
		return Limits{}, err
	}
	maxSessions, err := envNonNegativeInt("LOCALPROXY_DEFAULT_MAX_SESSIONS_PER_SECOND", defaultMaxSessionsPerSecond)
	if err != nil {
		return Limits{}, err
	}
	maxBackend, err := envPositiveIntFallback("LOCALPROXY_WEB_DEFAULT_MAX_BACKEND_CONNS", "LOCALPROXY_HTTP_DEFAULT_MAX_BACKEND_CONNS", defaultMaxBackendConns)
	if err != nil {
		return Limits{}, err
	}
	maxIdle, err := envNonNegativeIntFallback("LOCALPROXY_WEB_DEFAULT_MAX_IDLE_BACKEND_CONNS", "LOCALPROXY_HTTP_DEFAULT_MAX_IDLE_BACKEND_CONNS", defaultMaxIdleBackendConns)
	if err != nil {
		return Limits{}, err
	}
	queue := envStringFallback("LOCALPROXY_WEB_DEFAULT_QUEUE_TIMEOUT", "LOCALPROXY_HTTP_DEFAULT_QUEUE_TIMEOUT", defaultQueueTimeout)
	keepAlive := envStringFallback("LOCALPROXY_WEB_DEFAULT_HTTP_KEEPALIVE_TIMEOUT", "LOCALPROXY_HTTP_DEFAULT_HTTP_KEEPALIVE_TIMEOUT", defaultKeepAliveTimeout)
	tunnel := envStringFallback("LOCALPROXY_WEB_DEFAULT_TUNNEL_TIMEOUT", "LOCALPROXY_HTTP_DEFAULT_TUNNEL_TIMEOUT", defaultTunnelTimeout)
	for label, value := range map[string]string{
		"LOCALPROXY_WEB_DEFAULT_QUEUE_TIMEOUT":          queue,
		"LOCALPROXY_WEB_DEFAULT_HTTP_KEEPALIVE_TIMEOUT": keepAlive,
		"LOCALPROXY_WEB_DEFAULT_TUNNEL_TIMEOUT":         tunnel,
	} {
		if err := validateDuration(value, label); err != nil {
			return Limits{}, err
		}
	}

	return Limits{
		MaxTotalConns:        maxTotal,
		MaxSessionsPerSecond: maxSessions,
		MaxBackendConns:      maxBackend,
		MaxIdleBackendConns:  maxIdle,
		QueueTimeout:         queue,
		HTTPKeepAliveTimeout: keepAlive,
		TunnelTimeout:        tunnel,
	}, nil
}

func parseEnableConfig(host string, args []string) (Config, error) {
	limits, err := defaultLimits()
	if err != nil {
		return Config{}, err
	}

	cfg := Config{
		Host:         host,
		BindAddr:     envString("LOCALPROXY_BIND", "127.0.0.1"),
		HTTP3Policy:  envStringFallback("LOCALPROXY_WEB_HTTP3", "LOCALPROXY_HTTPS_HTTP3", defaultHTTP3Policy),
		FrontendALPN: envStringFallback("LOCALPROXY_WEB_FRONTEND_ALPN", "LOCALPROXY_HTTPS_FRONTEND_ALPN", defaultFrontendALPN),
		Limits:       limits,
	}
	cfg.FrontendCert = envStringFallback("LOCALPROXY_WEB_FRONTEND_CERT", "LOCALPROXY_HTTPS_FRONTEND_CERT", "")

	if err := validateHTTP3Policy(cfg.HTTP3Policy); err != nil {
		return Config{}, err
	}
	if err := validateFrontendALPN(cfg.FrontendALPN); err != nil {
		return Config{}, err
	}

	var specs []PortSpec
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "--":
			for _, raw := range args[i+1:] {
				spec, err := parseBarePort(raw)
				if err != nil {
					return Config{}, err
				}
				specs = append(specs, spec)
			}
			i = len(args)
		case arg == "--port":
			i++
			if i >= len(args) {
				return Config{}, usageErrorf("missing value for --port")
			}
			spec, err := parsePortSpec(args[i])
			if err != nil {
				return Config{}, err
			}
			specs = append(specs, spec)
		case strings.HasPrefix(arg, "--port="):
			spec, err := parsePortSpec(strings.TrimPrefix(arg, "--port="))
			if err != nil {
				return Config{}, err
			}
			specs = append(specs, spec)
		case arg == "--max-total-conns":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			cfg.Limits.MaxTotalConns, err = parsePositiveInt(value, arg)
			if err != nil {
				return Config{}, err
			}
		case strings.HasPrefix(arg, "--max-total-conns="):
			value := strings.TrimPrefix(arg, "--max-total-conns=")
			cfg.Limits.MaxTotalConns, err = parsePositiveInt(value, "--max-total-conns")
			if err != nil {
				return Config{}, err
			}
		case arg == "--max-sessions-per-second":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			cfg.Limits.MaxSessionsPerSecond, err = parseNonNegativeInt(value, arg)
			if err != nil {
				return Config{}, err
			}
		case strings.HasPrefix(arg, "--max-sessions-per-second="):
			value := strings.TrimPrefix(arg, "--max-sessions-per-second=")
			cfg.Limits.MaxSessionsPerSecond, err = parseNonNegativeInt(value, "--max-sessions-per-second")
			if err != nil {
				return Config{}, err
			}
		case arg == "--max-backend-conns":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			cfg.Limits.MaxBackendConns, err = parsePositiveInt(value, arg)
			if err != nil {
				return Config{}, err
			}
		case strings.HasPrefix(arg, "--max-backend-conns="):
			value := strings.TrimPrefix(arg, "--max-backend-conns=")
			cfg.Limits.MaxBackendConns, err = parsePositiveInt(value, "--max-backend-conns")
			if err != nil {
				return Config{}, err
			}
		case arg == "--max-idle-backend-conns":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			cfg.Limits.MaxIdleBackendConns, err = parseNonNegativeInt(value, arg)
			if err != nil {
				return Config{}, err
			}
		case strings.HasPrefix(arg, "--max-idle-backend-conns="):
			value := strings.TrimPrefix(arg, "--max-idle-backend-conns=")
			cfg.Limits.MaxIdleBackendConns, err = parseNonNegativeInt(value, "--max-idle-backend-conns")
			if err != nil {
				return Config{}, err
			}
		case arg == "--queue-timeout":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			if err := validateDuration(value, arg); err != nil {
				return Config{}, err
			}
			cfg.Limits.QueueTimeout = value
		case strings.HasPrefix(arg, "--queue-timeout="):
			value := strings.TrimPrefix(arg, "--queue-timeout=")
			if err := validateDuration(value, "--queue-timeout"); err != nil {
				return Config{}, err
			}
			cfg.Limits.QueueTimeout = value
		case arg == "--http-keepalive-timeout":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			if err := validateDuration(value, arg); err != nil {
				return Config{}, err
			}
			cfg.Limits.HTTPKeepAliveTimeout = value
		case strings.HasPrefix(arg, "--http-keepalive-timeout="):
			value := strings.TrimPrefix(arg, "--http-keepalive-timeout=")
			if err := validateDuration(value, "--http-keepalive-timeout"); err != nil {
				return Config{}, err
			}
			cfg.Limits.HTTPKeepAliveTimeout = value
		case arg == "--tunnel-timeout":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			if err := validateDuration(value, arg); err != nil {
				return Config{}, err
			}
			cfg.Limits.TunnelTimeout = value
		case strings.HasPrefix(arg, "--tunnel-timeout="):
			value := strings.TrimPrefix(arg, "--tunnel-timeout=")
			if err := validateDuration(value, "--tunnel-timeout"); err != nil {
				return Config{}, err
			}
			cfg.Limits.TunnelTimeout = value
		case arg == "--frontend-cert":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			cfg.FrontendCert = expandHome(value)
		case strings.HasPrefix(arg, "--frontend-cert="):
			cfg.FrontendCert = expandHome(strings.TrimPrefix(arg, "--frontend-cert="))
		case arg == "--http3":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			if err := validateHTTP3Policy(value); err != nil {
				return Config{}, err
			}
			cfg.HTTP3Policy = value
		case strings.HasPrefix(arg, "--http3="):
			value := strings.TrimPrefix(arg, "--http3=")
			if err := validateHTTP3Policy(value); err != nil {
				return Config{}, err
			}
			cfg.HTTP3Policy = value
		case arg == "--frontend-alpn":
			value, next, err := requireValue(args, i, arg)
			if err != nil {
				return Config{}, err
			}
			i = next
			if err := validateFrontendALPN(value); err != nil {
				return Config{}, err
			}
			cfg.FrontendALPN = value
		case strings.HasPrefix(arg, "--frontend-alpn="):
			value := strings.TrimPrefix(arg, "--frontend-alpn=")
			if err := validateFrontendALPN(value); err != nil {
				return Config{}, err
			}
			cfg.FrontendALPN = value
		case strings.HasPrefix(arg, "-"):
			return Config{}, usageErrorf("unknown option: %s", arg)
		default:
			spec, err := parseBarePort(arg)
			if err != nil {
				return Config{}, err
			}
			specs = append(specs, spec)
		}
	}

	if len(specs) == 0 {
		return Config{}, usageErrorf("enable needs at least one --port or bare TCP port")
	}
	if err := dedupePorts(specs); err != nil {
		return Config{}, err
	}

	sort.Slice(specs, func(i, j int) bool { return specs[i].Port < specs[j].Port })
	cfg.Ports = specs
	cfg.StateDir = hostDir(host)
	return cfg, nil
}

func finalizeEnableConfig(cfg Config) (Config, error) {
	needsCert := false
	for i := range cfg.Ports {
		if cfg.Ports[i].Mode != ModeWeb {
			continue
		}
		if cfg.Ports[i].Client == ClientHTTPS {
			needsCert = true
		}
		switch cfg.Ports[i].BackendPolicy {
		case BackendAuto:
			if probeBackendTLS(cfg.Host, cfg.Ports[i].Port) {
				cfg.Ports[i].BackendEffective = BackendHTTPS
			} else {
				cfg.Ports[i].BackendEffective = BackendHTTP
			}
		default:
			cfg.Ports[i].BackendEffective = cfg.Ports[i].BackendPolicy
		}
	}

	if needsCert {
		cert, err := ensureFrontendCert(cfg.FrontendCert, cfg.BindAddr)
		if err != nil {
			return Config{}, err
		}
		cfg.FrontendCert = cert
	}

	hasHTTPSClient := false
	for _, spec := range cfg.Ports {
		if spec.Mode == ModeWeb && spec.Client == ClientHTTPS {
			hasHTTPSClient = true
			break
		}
	}

	switch cfg.HTTP3Policy {
	case "auto":
		cfg.HTTP3Effective = hasHTTPSClient && isIPv4Address(cfg.BindAddr)
	case "on":
		if hasHTTPSClient && !isIPv4Address(cfg.BindAddr) {
			return Config{}, usageErrorf("--http3 on requires an IPv4 LOCALPROXY_BIND in v1")
		}
		cfg.HTTP3Effective = hasHTTPSClient
	case "off":
		cfg.HTTP3Effective = false
	default:
		return Config{}, usageErrorf("invalid --http3: %s", cfg.HTTP3Policy)
	}

	return cfg, nil
}

func requireValue(args []string, index int, label string) (string, int, error) {
	next := index + 1
	if next >= len(args) {
		return "", index, usageErrorf("missing value for %s", label)
	}
	return args[next], next, nil
}

func parsePositiveInt(value, label string) (int, error) {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 1 {
		return 0, usageErrorf("invalid %s: %s", label, value)
	}
	return parsed, nil
}

func parseNonNegativeInt(value, label string) (int, error) {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		return 0, usageErrorf("invalid %s: %s", label, value)
	}
	return parsed, nil
}

func validateDuration(value, label string) error {
	if value == "" {
		return usageErrorf("invalid %s: %s", label, value)
	}
	for _, suffix := range []string{"ms", "s", "m", "h", "d"} {
		if strings.HasSuffix(value, suffix) {
			number := strings.TrimSuffix(value, suffix)
			if number == "" || strings.HasPrefix(number, "-") {
				return usageErrorf("invalid %s: %s", label, value)
			}
			parsed, err := strconv.Atoi(number)
			if err != nil || parsed < 0 {
				return usageErrorf("invalid %s: %s", label, value)
			}
			return nil
		}
	}
	if strings.HasPrefix(value, "-") {
		return usageErrorf("invalid %s: %s", label, value)
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		return usageErrorf("invalid %s: %s", label, value)
	}
	return nil
}

func validateHTTP3Policy(value string) error {
	if value != "auto" && value != "on" && value != "off" {
		return usageErrorf("invalid --http3: %s", value)
	}
	return nil
}

func validateFrontendALPN(value string) error {
	if value != "h2,http/1.1" && value != "http/1.1" {
		return usageErrorf("invalid --frontend-alpn: %s", value)
	}
	return nil
}

func envString(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func envStringFallback(primary, secondary, fallback string) string {
	if value := os.Getenv(primary); value != "" {
		return value
	}
	if value := os.Getenv(secondary); value != "" {
		return value
	}
	return fallback
}

func envPositiveInt(name string, fallback int) (int, error) {
	if value := os.Getenv(name); value != "" {
		return parsePositiveInt(value, name)
	}
	return fallback, nil
}

func envNonNegativeInt(name string, fallback int) (int, error) {
	if value := os.Getenv(name); value != "" {
		return parseNonNegativeInt(value, name)
	}
	return fallback, nil
}

func envPositiveIntFallback(primary, secondary string, fallback int) (int, error) {
	if value := os.Getenv(primary); value != "" {
		return parsePositiveInt(value, primary)
	}
	if value := os.Getenv(secondary); value != "" {
		return parsePositiveInt(value, secondary)
	}
	return fallback, nil
}

func envNonNegativeIntFallback(primary, secondary string, fallback int) (int, error) {
	if value := os.Getenv(primary); value != "" {
		return parseNonNegativeInt(value, primary)
	}
	if value := os.Getenv(secondary); value != "" {
		return parseNonNegativeInt(value, secondary)
	}
	return fallback, nil
}

func stateRoot() string {
	if value := os.Getenv("XDG_STATE_HOME"); value != "" {
		return filepath.Join(value, "localproxy")
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return filepath.Join(".", ".local", "state", "localproxy")
	}
	return filepath.Join(home, ".local", "state", "localproxy")
}

func configRoot() string {
	if value := os.Getenv("XDG_CONFIG_HOME"); value != "" {
		return filepath.Join(value, "localproxy")
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return filepath.Join(".", ".config", "localproxy")
	}
	return filepath.Join(home, ".config", "localproxy")
}

func hostDir(host string) string {
	return filepath.Join(stateRoot(), host)
}

func configPath(dir string) string {
	return filepath.Join(dir, "haproxy.cfg")
}

func statePath(dir string) string {
	return filepath.Join(dir, "state.json")
}

func pidPath(dir string) string {
	return filepath.Join(dir, "haproxy.pid")
}

func socketPath(dir string) string {
	return filepath.Join(dir, "haproxy.sock")
}

func defaultCertPath() string {
	return filepath.Join(configRoot(), "localproxy.pem")
}

func expandHome(path string) string {
	if path == "~" {
		home, err := os.UserHomeDir()
		if err == nil && home != "" {
			return home
		}
	}
	if strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err == nil && home != "" {
			return filepath.Join(home, strings.TrimPrefix(path, "~/"))
		}
	}
	return path
}

func isIPv4Address(value string) bool {
	ip := net.ParseIP(value)
	return ip != nil && ip.To4() != nil
}

func saveState(cfg Config) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal state: %w", err)
	}
	return os.WriteFile(statePath(cfg.StateDir), append(data, '\n'), 0o600)
}

func loadState(dir string) (Config, error) {
	data, err := os.ReadFile(statePath(dir))
	if err != nil {
		return Config{}, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, err
	}
	return cfg, nil
}
