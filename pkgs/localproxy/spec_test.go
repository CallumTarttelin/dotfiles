package main

import "testing"

func TestParsePortSpecTCP(t *testing.T) {
	spec, err := parsePortSpec("22:tcp")
	if err != nil {
		t.Fatal(err)
	}
	if spec.Port != 22 || spec.ListenPort != 22 || spec.TargetPort != 22 || spec.Mode != ModeTCP {
		t.Fatalf("unexpected spec: %#v", spec)
	}
}

func TestParsePortSpecTCPRemap(t *testing.T) {
	spec, err := parsePortSpec("2222:tcp,target=22")
	if err != nil {
		t.Fatal(err)
	}
	if spec.Port != 2222 || spec.ListenPort != 2222 || spec.TargetPort != 22 || spec.Mode != ModeTCP {
		t.Fatalf("unexpected spec: %#v", spec)
	}
}

func TestParsePortSpecWeb(t *testing.T) {
	spec, err := parsePortSpec("5173:client=http,backend=https")
	if err != nil {
		t.Fatal(err)
	}
	if spec.Port != 5173 || spec.Mode != ModeWeb || spec.Client != ClientHTTP || spec.BackendPolicy != BackendHTTPS {
		t.Fatalf("unexpected spec: %#v", spec)
	}
}

func TestParseBarePortAsTCP(t *testing.T) {
	spec, err := parsePortSpec("5432")
	if err != nil {
		t.Fatal(err)
	}
	if spec.Port != 5432 || spec.ListenPort != 5432 || spec.TargetPort != 5432 || spec.Mode != ModeTCP {
		t.Fatalf("unexpected spec: %#v", spec)
	}
}

func TestParsePortSpecRejectsInvalidClient(t *testing.T) {
	_, err := parsePortSpec("5173:client=ftp,backend=http")
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestParsePortSpecRejectsDuplicateKeys(t *testing.T) {
	_, err := parsePortSpec("5173:client=http,client=https,backend=http")
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestParsePortSpecRejectsDuplicateTCPTarget(t *testing.T) {
	_, err := parsePortSpec("2222:tcp,target=22,target=23")
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestParsePortSpecRejectsUnknownTCPKey(t *testing.T) {
	_, err := parsePortSpec("2222:tcp,foo=22")
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestParsePortSpecRejectsInvalidTCPTarget(t *testing.T) {
	for _, value := range []string{"2222:tcp,target=0", "2222:tcp,target=65536", "2222:tcp,target=abc"} {
		if _, err := parsePortSpec(value); err == nil {
			t.Fatalf("expected %q to fail", value)
		}
	}
}

func TestDedupePortsRejectsDuplicateListenPorts(t *testing.T) {
	err := dedupePorts([]PortSpec{
		tcpPortSpec(3000, 22),
		{Port: 3000, ListenPort: 3000, TargetPort: 3000, Mode: ModeWeb, Client: ClientHTTP, BackendPolicy: BackendHTTP},
	})
	if err == nil {
		t.Fatal("expected duplicate port error")
	}
}

func TestDedupePortsAllowsDuplicateTargetPorts(t *testing.T) {
	err := dedupePorts([]PortSpec{
		tcpPortSpec(2222, 22),
		tcpPortSpec(2223, 22),
	})
	if err != nil {
		t.Fatalf("unexpected duplicate port error: %v", err)
	}
}

func TestNormalizePortSpecLeavesWebPortsAlone(t *testing.T) {
	spec := normalizePortSpec(PortSpec{
		Port:          3000,
		Mode:          ModeWeb,
		Client:        ClientHTTP,
		BackendPolicy: BackendHTTP,
	})
	if spec.ListenPort != 0 || spec.TargetPort != 0 {
		t.Fatalf("web spec should not get TCP remap fields: %#v", spec)
	}
}
