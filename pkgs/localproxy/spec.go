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
	return PortSpec{Port: port, Mode: ModeTCP}, nil
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
		return PortSpec{Port: port, Mode: ModeTCP}, nil
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

func dedupePorts(specs []PortSpec) error {
	seen := map[int]bool{}
	for _, spec := range specs {
		if seen[spec.Port] {
			return usageErrorf("duplicate port: %d", spec.Port)
		}
		seen[spec.Port] = true
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
	if spec.Mode == ModeTCP {
		return fmt.Sprintf("%d=tcp", spec.Port)
	}
	return fmt.Sprintf("%d=client:%s,backend:%s,effective:%s", spec.Port, spec.Client, spec.BackendPolicy, spec.BackendEffective)
}

func splitPortKinds(specs []PortSpec) (tcp []PortSpec, web []PortSpec) {
	for _, spec := range specs {
		if spec.Mode == ModeTCP {
			tcp = append(tcp, spec)
		} else {
			web = append(web, spec)
		}
	}
	return tcp, web
}
