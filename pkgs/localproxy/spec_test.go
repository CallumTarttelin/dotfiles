package main

import "testing"

func TestParsePortSpecTCP(t *testing.T) {
	spec, err := parsePortSpec("22:tcp")
	if err != nil {
		t.Fatal(err)
	}
	if spec.Port != 22 || spec.Mode != ModeTCP {
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
	if spec.Port != 5432 || spec.Mode != ModeTCP {
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

func TestDedupePortsRejectsDuplicates(t *testing.T) {
	err := dedupePorts([]PortSpec{
		{Port: 3000, Mode: ModeTCP},
		{Port: 3000, Mode: ModeWeb, Client: ClientHTTP, BackendPolicy: BackendHTTP},
	})
	if err == nil {
		t.Fatal("expected duplicate port error")
	}
}
