package main

import (
	"encoding/csv"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type portStats struct {
	QCur    string
	SCur    string
	CumReq  string
	CumConn string
}

func statusAll() error {
	root := stateRoot()
	entries, err := os.ReadDir(root)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Println("no local proxies configured")
			return nil
		}
		return err
	}
	hosts := make([]string, 0)
	for _, entry := range entries {
		if !entry.IsDir() || entry.Name() == "http" || entry.Name() == "https" {
			continue
		}
		if _, err := os.Stat(statePath(filepath.Join(root, entry.Name()))); err == nil {
			hosts = append(hosts, entry.Name())
		}
	}
	sort.Strings(hosts)
	if len(hosts) == 0 {
		fmt.Println("no local proxies configured")
		return nil
	}
	for _, host := range hosts {
		if err := statusOne(host); err != nil {
			return err
		}
	}
	return nil
}

func statusOne(host string) error {
	dir := hostDir(host)
	cfg, err := loadState(dir)
	state := "not configured"
	if pid, ok := alivePID(pidPath(dir)); ok {
		state = fmt.Sprintf("running pid %d", pid)
	} else if _, statErr := os.Stat(dir); statErr == nil {
		state = "stopped"
	}
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Printf("%s: %s\n", host, state)
			return nil
		}
		return err
	}

	parts := []string{fmt.Sprintf("%s: %s", host, state)}
	parts = append(parts, fmt.Sprintf("bind: %s", cfg.BindAddr))
	parts = append(parts, fmt.Sprintf("ports: %s", statusPortSpecs(cfg.Ports)))
	parts = append(parts, fmt.Sprintf("max-total-conns: %d", cfg.Limits.MaxTotalConns))
	parts = append(parts, fmt.Sprintf("max-sessions-per-second: %d", cfg.Limits.MaxSessionsPerSecond))
	if hasWebPorts(cfg.Ports) {
		parts = append(parts, fmt.Sprintf("max-backend-conns: %d", cfg.Limits.MaxBackendConns))
		parts = append(parts, fmt.Sprintf("max-idle-backend-conns: %d", cfg.Limits.MaxIdleBackendConns))
		parts = append(parts, fmt.Sprintf("queue-timeout: %s", cfg.Limits.QueueTimeout))
		parts = append(parts, fmt.Sprintf("http-keepalive-timeout: %s", cfg.Limits.HTTPKeepAliveTimeout))
		parts = append(parts, fmt.Sprintf("tunnel-timeout: %s", cfg.Limits.TunnelTimeout))
	}
	if hasHTTPSClientPorts(cfg.Ports) {
		parts = append(parts, fmt.Sprintf("frontend-cert: %s", cfg.FrontendCert))
		parts = append(parts, fmt.Sprintf("http3: %s effective: %s", cfg.HTTP3Policy, onOff(cfg.HTTP3Effective)))
		parts = append(parts, fmt.Sprintf("frontend-alpn: %s", cfg.FrontendALPN))
	}

	if strings.HasPrefix(state, "running pid ") {
		if info, err := querySocket(socketPath(dir), "show info\n"); err == nil && info != "" {
			infoMap := parseInfo(info)
			live := []string{}
			for _, key := range []string{"CurrConns", "ConnRate", "CumConns"} {
				if value := infoMap[key]; value != "" {
					live = append(live, fmt.Sprintf("%s: %s", key, value))
				}
			}
			if len(live) > 0 {
				parts = append(parts, strings.Join(live, ", "))
			}
		}
		if stats, err := querySocket(socketPath(dir), "show stat\n"); err == nil && stats != "" {
			if summaries := summarizeWebStats(cfg, stats); len(summaries) > 0 {
				parts = append(parts, "port-stats: "+strings.Join(summaries, ", "))
			}
		}
	}

	fmt.Println(strings.Join(parts, ", "))
	return nil
}

func statusPortSpecs(specs []PortSpec) string {
	parts := make([]string, 0, len(specs))
	for _, spec := range specs {
		if spec.Mode == ModeTCP {
			parts = append(parts, fmt.Sprintf("%d[tcp]", spec.Port))
		} else {
			parts = append(parts, fmt.Sprintf("%d[client=%s,backend=%s,effective=%s]", spec.Port, spec.Client, spec.BackendPolicy, spec.BackendEffective))
		}
	}
	return strings.Join(parts, " ")
}

func hasWebPorts(specs []PortSpec) bool {
	for _, spec := range specs {
		if spec.Mode == ModeWeb {
			return true
		}
	}
	return false
}

func hasHTTPSClientPorts(specs []PortSpec) bool {
	for _, spec := range specs {
		if spec.Mode == ModeWeb && spec.Client == ClientHTTPS {
			return true
		}
	}
	return false
}

func onOff(value bool) string {
	if value {
		return "on"
	}
	return "off"
}

func querySocket(path string, command string) (string, error) {
	conn, err := net.DialTimeout("unix", path, time.Second)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(time.Second))
	if _, err := io.WriteString(conn, command); err != nil {
		return "", err
	}
	data, err := io.ReadAll(conn)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func parseInfo(text string) map[string]string {
	out := map[string]string{}
	for _, line := range strings.Split(text, "\n") {
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		out[strings.TrimSpace(key)] = strings.TrimSpace(value)
	}
	return out
}

func summarizeWebStats(cfg Config, text string) []string {
	reader := csv.NewReader(strings.NewReader(text))
	reader.FieldsPerRecord = -1
	rows, err := reader.ReadAll()
	if err != nil || len(rows) == 0 {
		return nil
	}
	header := rows[0]
	index := map[string]int{}
	for i, name := range header {
		name = strings.TrimPrefix(strings.TrimSpace(name), "# ")
		index[name] = i
	}

	safeHost := safeName(cfg.Host)
	stats := map[int]portStats{}
	for _, row := range rows[1:] {
		pxname := csvValue(row, index, "pxname")
		svname := csvValue(row, index, "svname")
		for _, spec := range cfg.Ports {
			if spec.Mode != ModeWeb {
				continue
			}
			frontend := fmt.Sprintf("localproxy_web_%s_%d", safeHost, spec.Port)
			backend := frontend + "_backend"
			current := stats[spec.Port]
			if pxname == frontend && svname == "FRONTEND" {
				if value := csvValue(row, index, "req_tot"); value != "" {
					current.CumReq = value
				}
				if value := csvValue(row, index, "stot"); value != "" {
					current.CumConn = value
				}
			}
			if pxname == backend && svname == "BACKEND" {
				if value := csvValue(row, index, "qcur"); value != "" {
					current.QCur = value
				}
				if value := csvValue(row, index, "req_tot"); value != "" {
					current.CumReq = value
				}
			}
			if pxname == backend && svname == "target" {
				if value := csvValue(row, index, "scur"); value != "" {
					current.SCur = value
				}
				if value := csvValue(row, index, "stot"); value != "" {
					current.CumConn = value
				}
			}
			stats[spec.Port] = current
		}
	}

	ports := make([]int, 0, len(stats))
	for port := range stats {
		ports = append(ports, port)
	}
	sort.Ints(ports)
	out := make([]string, 0, len(ports))
	for _, port := range ports {
		stat := stats[port]
		out = append(out, fmt.Sprintf("%d[qcur=%s scur=%s cumreq=%s cumconn=%s]", port, stat.QCur, stat.SCur, stat.CumReq, stat.CumConn))
	}
	return out
}

func csvValue(row []string, index map[string]int, name string) string {
	i, ok := index[name]
	if !ok || i >= len(row) {
		return ""
	}
	return row[i]
}

func pidStatus(dir string) string {
	if pid, ok := alivePID(pidPath(dir)); ok {
		return "running pid " + strconv.Itoa(pid)
	}
	if _, err := os.Stat(dir); err == nil {
		return "stopped"
	}
	return "not configured"
}
