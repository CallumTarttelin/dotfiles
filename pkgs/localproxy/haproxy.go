package main

import (
	"bytes"
	"crypto/tls"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var defaultHaproxy = "haproxy"

func haproxyPath() string {
	if value := os.Getenv("LOCALPROXY_HAPROXY"); value != "" {
		return value
	}
	return defaultHaproxy
}

func probeBackendTLS(host string, port int) bool {
	dialer := &net.Dialer{Timeout: 2 * time.Second}
	conn, err := tls.DialWithDialer(dialer, "tcp", net.JoinHostPort(host, strconv.Itoa(port)), &tls.Config{
		InsecureSkipVerify: true,
		ServerName:         host,
		NextProtos:         []string{"h2", "http/1.1"},
	})
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func renderConfig(cfg Config) string {
	tcpPorts, webPorts := splitPortKinds(cfg.Ports)
	safeHost := safeName(cfg.Host)
	var out strings.Builder

	out.WriteString("# localproxy-mode: unified\n")
	out.WriteString(fmt.Sprintf("# localproxy-host: %s\n", cfg.Host))
	out.WriteString(fmt.Sprintf("# localproxy-bind: %s\n", cfg.BindAddr))
	out.WriteString(fmt.Sprintf("# localproxy-port-specs: %s\n", metadataPortSpecs(cfg.Ports)))
	out.WriteString(fmt.Sprintf("# localproxy-frontend-cert: %s\n", cfg.FrontendCert))
	out.WriteString(fmt.Sprintf("# localproxy-http3: %s\n", cfg.HTTP3Policy))
	out.WriteString(fmt.Sprintf("# localproxy-http3-effective: %t\n", cfg.HTTP3Effective))
	out.WriteString(fmt.Sprintf("# localproxy-frontend-alpn: %s\n", cfg.FrontendALPN))
	out.WriteString(fmt.Sprintf("# localproxy-max-total-conns: %d\n", cfg.Limits.MaxTotalConns))
	out.WriteString(fmt.Sprintf("# localproxy-max-sessions-per-second: %d\n", cfg.Limits.MaxSessionsPerSecond))
	out.WriteString(fmt.Sprintf("# localproxy-max-backend-conns: %d\n", cfg.Limits.MaxBackendConns))
	out.WriteString(fmt.Sprintf("# localproxy-max-idle-backend-conns: %d\n", cfg.Limits.MaxIdleBackendConns))
	out.WriteString(fmt.Sprintf("# localproxy-queue-timeout: %s\n", cfg.Limits.QueueTimeout))
	out.WriteString(fmt.Sprintf("# localproxy-http-keepalive-timeout: %s\n", cfg.Limits.HTTPKeepAliveTimeout))
	out.WriteString(fmt.Sprintf("# localproxy-tunnel-timeout: %s\n", cfg.Limits.TunnelTimeout))
	out.WriteString("global\n")
	out.WriteString("  daemon\n")
	out.WriteString(fmt.Sprintf("  maxconn %d\n", cfg.Limits.MaxTotalConns))
	if needsExperimental(cfg.Ports) {
		out.WriteString("  expose-experimental-directives\n")
	}
	out.WriteString(fmt.Sprintf("  stats socket %s mode 600 level operator\n\n", socketPath(cfg.StateDir)))

	if len(tcpPorts) > 0 {
		out.WriteString("defaults localproxy_tcp_defaults\n")
		out.WriteString("  mode tcp\n")
		out.WriteString("  option tcpka\n")
		out.WriteString("  timeout connect 5s\n")
		out.WriteString("  timeout client 1h\n")
		out.WriteString("  timeout server 1h\n\n")
		out.WriteString(fmt.Sprintf("frontend localproxy_tcp_%s\n", safeHost))
		out.WriteString(fmt.Sprintf("  maxconn %d\n", cfg.Limits.MaxTotalConns))
		if cfg.Limits.MaxSessionsPerSecond > 0 {
			out.WriteString(fmt.Sprintf("  rate-limit sessions %d\n", cfg.Limits.MaxSessionsPerSecond))
		}
		for _, spec := range tcpPorts {
			out.WriteString(fmt.Sprintf("  bind %s:%d backlog 64\n", cfg.BindAddr, spec.Port))
			out.WriteString(fmt.Sprintf("  use_backend localproxy_tcp_%s_%d_backend if { dst_port %d }\n", safeHost, spec.Port, spec.Port))
		}
		out.WriteByte('\n')
		for _, spec := range tcpPorts {
			out.WriteString(fmt.Sprintf("backend localproxy_tcp_%s_%d_backend\n", safeHost, spec.Port))
			out.WriteString(fmt.Sprintf("  server target %s:%d maxconn %d\n\n", cfg.Host, spec.Port, cfg.Limits.MaxTotalConns))
		}
	}

	if len(webPorts) > 0 {
		out.WriteString("defaults localproxy_web_defaults\n")
		out.WriteString("  mode http\n")
		out.WriteString("  option http-keep-alive\n")
		out.WriteString("  timeout connect 5s\n")
		out.WriteString("  timeout client 1h\n")
		out.WriteString("  timeout server 1h\n")
		out.WriteString("  timeout http-request 5s\n")
		out.WriteString(fmt.Sprintf("  timeout http-keep-alive %s\n", cfg.Limits.HTTPKeepAliveTimeout))
		out.WriteString(fmt.Sprintf("  timeout queue %s\n", cfg.Limits.QueueTimeout))
		out.WriteString(fmt.Sprintf("  timeout tunnel %s\n\n", cfg.Limits.TunnelTimeout))

		for _, spec := range webPorts {
			frontend := fmt.Sprintf("localproxy_web_%s_%d", safeHost, spec.Port)
			backend := fmt.Sprintf("%s_backend", frontend)
			out.WriteString(fmt.Sprintf("frontend %s\n", frontend))
			if spec.Client == ClientHTTPS {
				out.WriteString(fmt.Sprintf("  bind %s:%d ssl crt %s alpn %s\n", cfg.BindAddr, spec.Port, cfg.FrontendCert, cfg.FrontendALPN))
				if cfg.HTTP3Effective {
					out.WriteString(fmt.Sprintf("  bind quic4@%s:%d ssl crt %s alpn h3\n", cfg.BindAddr, spec.Port, cfg.FrontendCert))
					out.WriteString(fmt.Sprintf("  http-response set-header alt-svc 'h3=\":%d\";ma=900;'\n", spec.Port))
				}
			} else {
				out.WriteString(fmt.Sprintf("  bind %s:%d\n", cfg.BindAddr, spec.Port))
			}
			out.WriteString(fmt.Sprintf("  http-request set-header X-Forwarded-Proto %s\n", spec.Client))
			out.WriteString("  http-request set-header X-Forwarded-Host %[req.hdr(Host)]\n")
			out.WriteString(fmt.Sprintf("  http-request set-header X-Forwarded-Port %d\n", spec.Port))
			out.WriteString(fmt.Sprintf("  default_backend %s\n\n", backend))
			out.WriteString(fmt.Sprintf("backend %s\n", backend))
			out.WriteString("  http-reuse safe\n")
			out.WriteString(fmt.Sprintf("  server target %s maxconn %d pool-max-conn %d pool-purge-delay 30s\n\n",
				backendTarget(cfg.Host, spec), cfg.Limits.MaxBackendConns, cfg.Limits.MaxIdleBackendConns))
		}
	}

	return out.String()
}

func metadataPortSpecs(specs []PortSpec) string {
	parts := make([]string, 0, len(specs))
	for _, spec := range specs {
		parts = append(parts, portSpecText(spec))
	}
	return strings.Join(parts, " ")
}

func needsExperimental(specs []PortSpec) bool {
	for _, spec := range specs {
		if spec.Mode == ModeWeb && spec.BackendEffective == BackendH3 {
			return true
		}
	}
	return false
}

func backendTarget(host string, spec PortSpec) string {
	switch spec.BackendEffective {
	case BackendHTTPS:
		return fmt.Sprintf("%s:%d ssl verify none sni str(%s) alpn h2,http/1.1", host, spec.Port, host)
	case BackendH3:
		return fmt.Sprintf("quic4@%s:%d ssl verify none sni str(%s) alpn h3", host, spec.Port, host)
	default:
		return fmt.Sprintf("%s:%d", host, spec.Port)
	}
}

func validateConfigFile(path string) error {
	cmd := exec.Command(haproxyPath(), "-c", "-f", path)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("haproxy validation failed: %w\n%s", err, bytes.TrimSpace(output))
	}
	return nil
}

func validateConfigWithAutoHTTP3Fallback(cfg Config) (Config, string, error) {
	rendered := renderConfig(cfg)
	if err := os.WriteFile(configPath(cfg.StateDir), []byte(rendered), 0o600); err != nil {
		return Config{}, "", fmt.Errorf("write haproxy config: %w", err)
	}
	if err := validateConfigFile(configPath(cfg.StateDir)); err != nil {
		if cfg.HTTP3Policy == "auto" && cfg.HTTP3Effective {
			cfg.HTTP3Effective = false
			rendered = renderConfig(cfg)
			if writeErr := os.WriteFile(configPath(cfg.StateDir), []byte(rendered), 0o600); writeErr != nil {
				return Config{}, "", fmt.Errorf("write fallback haproxy config: %w", writeErr)
			}
			if fallbackErr := validateConfigFile(configPath(cfg.StateDir)); fallbackErr != nil {
				return Config{}, "", fallbackErr
			}
			return cfg, rendered, nil
		}
		return Config{}, "", err
	}
	return cfg, rendered, nil
}

func enableHAProxy(cfg Config) error {
	if err := os.MkdirAll(cfg.StateDir, 0o700); err != nil {
		return fmt.Errorf("create state dir: %w", err)
	}

	finalCfg, _, err := validateConfigWithAutoHTTP3Fallback(cfg)
	if err != nil {
		return err
	}
	if err := saveState(finalCfg); err != nil {
		return err
	}
	return launchHAProxy(finalCfg.StateDir)
}

func launchHAProxy(dir string) error {
	pidfile := pidPath(dir)
	cfgfile := configPath(dir)
	if pid, ok := alivePID(pidfile); ok {
		cmd := exec.Command(haproxyPath(), "-f", cfgfile, "-D", "-p", pidfile, "-sf", strconv.Itoa(pid))
		output, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("haproxy reload failed: %w\n%s", err, bytes.TrimSpace(output))
		}
		return nil
	}
	_ = os.Remove(pidfile)
	cmd := exec.Command(haproxyPath(), "-f", cfgfile, "-D", "-p", pidfile)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("haproxy launch failed: %w\n%s", err, bytes.TrimSpace(output))
	}
	return nil
}

func cleanupLegacyHost(host string) {
	for _, legacy := range []string{"http", "https"} {
		stopAndRemoveDir(filepath.Join(stateRoot(), legacy, host))
	}
}

func stopAndRemoveDir(dir string) {
	pidfile := pidPath(dir)
	if pid, ok := alivePID(pidfile); ok {
		_ = syscall.Kill(pid, syscall.SIGTERM)
		for i := 0; i < 50; i++ {
			if !processAlive(pid) {
				break
			}
			time.Sleep(100 * time.Millisecond)
		}
	}
	_ = os.RemoveAll(dir)
}

func alivePID(pidfile string) (int, bool) {
	data, err := os.ReadFile(pidfile)
	if err != nil {
		return 0, false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil || pid < 1 {
		return 0, false
	}
	if !processAlive(pid) {
		return 0, false
	}
	return pid, true
}

func processAlive(pid int) bool {
	err := syscall.Kill(pid, 0)
	return err == nil
}
