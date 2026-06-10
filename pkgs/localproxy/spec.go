package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

type Mode string
type ClientProto string
type BackendProto string

const (
	ModeTCP Mode = "tcp"
	ModeWeb Mode = "web"

	ClientHTTP  ClientProto = "http"
	ClientHTTPS ClientProto = "https"

	BackendAuto  BackendProto = "auto"
	BackendHTTP  BackendProto = "http"
	BackendHTTPS BackendProto = "https"
	BackendH3    BackendProto = "h3"
)

var hostRe = regexp.MustCompile(`^[A-Za-z0-9_.-]+$`)

type PortSpec struct {
	Port             int          `json:"port"`
	ListenPort       int          `json:"listen_port,omitempty"`
	TargetPort       int          `json:"target_port,omitempty"`
	Mode             Mode         `json:"mode"`
	Client           ClientProto  `json:"client,omitempty"`
	BackendPolicy    BackendProto `json:"backend_policy,omitempty"`
	BackendEffective BackendProto `json:"backend_effective,omitempty"`
}

func validateHost(host string) error {
	if !hostRe.MatchString(host) {
		return usageErrorf("invalid host: %s", host)
	}
	return nil
}

func validatePort(port int) error {
	if port < 1 || port > 65535 {
		return usageErrorf("invalid port: %d", port)
	}
	return nil
}

func parsePortNumber(value string) (int, error) {
	if value == "" {
		return 0, usageErrorf("missing port")
	}
	port, err := strconv.Atoi(value)
	if err != nil {
		return 0, usageErrorf("invalid port: %s", value)
	}
	if err := validatePort(port); err != nil {
		return 0, err
	}
	return port, nil
}

func parseBarePort(value string) (PortSpec, error) {
	port, err := parsePortNumber(value)
	if err != nil {
		return PortSpec{}, err
	}
	return tcpPortSpec(port, port), nil
}

func parsePortSpec(value string) (PortSpec, error) {
	portPart, rest, ok := strings.Cut(value, ":")
	if !ok {
		return parseBarePort(value)
	}

	port, err := parsePortNumber(portPart)
	if err != nil {
		return PortSpec{}, err
	}
	if rest == "tcp" {
		return tcpPortSpec(port, port), nil
	}
	if strings.HasPrefix(rest, "tcp,") {
		return parseTCPPortSpec(port, strings.TrimPrefix(rest, "tcp,"))
	}
	if rest == "" {
		return PortSpec{}, usageErrorf("invalid --port spec: %s", value)
	}

	parsed := PortSpec{
		Port:          port,
		Mode:          ModeWeb,
		BackendPolicy: BackendAuto,
	}
	seen := map[string]bool{}

	for _, item := range strings.Split(rest, ",") {
		key, raw, ok := strings.Cut(item, "=")
		if !ok || key == "" || raw == "" {
			return PortSpec{}, usageErrorf("invalid --port spec item: %s", item)
		}
		if seen[key] {
			return PortSpec{}, usageErrorf("duplicate --port spec key: %s", key)
		}
		seen[key] = true

		switch key {
		case "client":
			client := ClientProto(raw)
			if client != ClientHTTP && client != ClientHTTPS {
				return PortSpec{}, usageErrorf("invalid client protocol for port %d: %s", port, raw)
			}
			parsed.Client = client
		case "backend":
			backend := BackendProto(raw)
			if backend != BackendAuto && backend != BackendHTTP && backend != BackendHTTPS && backend != BackendH3 {
				return PortSpec{}, usageErrorf("invalid backend protocol for port %d: %s", port, raw)
			}
			parsed.BackendPolicy = backend
		default:
			return PortSpec{}, usageErrorf("unknown --port spec key: %s", key)
		}
	}

	if parsed.Client == "" {
		return PortSpec{}, usageErrorf("missing client protocol for port %d", port)
	}
	return parsed, nil
}

func parseTCPPortSpec(listenPort int, rest string) (PortSpec, error) {
	parsed := tcpPortSpec(listenPort, listenPort)
	seen := map[string]bool{}

	for _, item := range strings.Split(rest, ",") {
		key, raw, ok := strings.Cut(item, "=")
		if !ok || key == "" || raw == "" {
			return PortSpec{}, usageErrorf("invalid --port spec item: %s", item)
		}
		if seen[key] {
			return PortSpec{}, usageErrorf("duplicate --port spec key: %s", key)
		}
		seen[key] = true

		switch key {
		case "target":
			target, err := parsePortNumber(raw)
			if err != nil {
				return PortSpec{}, err
			}
			parsed.TargetPort = target
		default:
			return PortSpec{}, usageErrorf("unknown --port spec key: %s", key)
		}
	}

	return parsed, nil
}

func tcpPortSpec(listenPort int, targetPort int) PortSpec {
	return PortSpec{
		Port:       listenPort,
		ListenPort: listenPort,
		TargetPort: targetPort,
		Mode:       ModeTCP,
	}
}

func normalizePortSpec(spec PortSpec) PortSpec {
	if spec.Mode != ModeTCP {
		return spec
	}
	if spec.ListenPort == 0 {
		spec.ListenPort = spec.Port
	}
	if spec.Port == 0 {
		spec.Port = spec.ListenPort
	}
	if spec.TargetPort == 0 {
		spec.TargetPort = spec.ListenPort
	}
	return spec
}

func normalizePortSpecs(specs []PortSpec) []PortSpec {
	out := make([]PortSpec, len(specs))
	for i, spec := range specs {
		out[i] = normalizePortSpec(spec)
	}
	return out
}

func effectiveListenPort(spec PortSpec) int {
	if spec.Mode == ModeTCP {
		return normalizePortSpec(spec).ListenPort
	}
	return spec.Port
}

func dedupePorts(specs []PortSpec) error {
	seen := map[int]bool{}
	for _, spec := range specs {
		port := effectiveListenPort(spec)
		if seen[port] {
			return usageErrorf("duplicate port: %d", port)
		}
		seen[port] = true
	}
	return nil
}

func safeName(value string) string {
	var out strings.Builder
	for _, r := range value {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' {
			out.WriteRune(r)
		} else {
			out.WriteByte('_')
		}
	}
	return out.String()
}

func portSpecText(spec PortSpec) string {
	spec = normalizePortSpec(spec)
	if spec.Mode == ModeTCP {
		if spec.TargetPort == spec.ListenPort {
			return fmt.Sprintf("%d=tcp", spec.ListenPort)
		}
		return fmt.Sprintf("%d=tcp,target=%d", spec.ListenPort, spec.TargetPort)
	}
	return fmt.Sprintf("%d=client:%s,backend:%s,effective:%s", spec.Port, spec.Client, spec.BackendPolicy, spec.BackendEffective)
}

func splitPortKinds(specs []PortSpec) (tcp []PortSpec, web []PortSpec) {
	for _, spec := range specs {
		spec = normalizePortSpec(spec)
		if spec.Mode == ModeTCP {
			tcp = append(tcp, spec)
		} else {
			web = append(web, spec)
		}
	}
	return tcp, web
}
