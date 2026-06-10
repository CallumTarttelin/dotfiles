package main

import (
	"strings"
	"testing"
)

func TestRenderConfigTCPRemap(t *testing.T) {
	cfg := Config{
		Host:     "devbox",
		BindAddr: "127.0.0.1",
		StateDir: t.TempDir(),
		Ports: []PortSpec{
			tcpPortSpec(2222, 22),
		},
		Limits: Limits{
			MaxTotalConns: 1000,
		},
	}

	rendered := renderConfig(cfg)
	for _, want := range []string{
		"bind 127.0.0.1:2222 backlog 64",
		"use_backend localproxy_tcp_devbox_2222_backend if { dst_port 2222 }",
		"backend localproxy_tcp_devbox_2222_backend",
		"server target devbox:22 maxconn 1000",
	} {
		if !strings.Contains(rendered, want) {
			t.Fatalf("rendered config missing %q:\n%s", want, rendered)
		}
	}
}
