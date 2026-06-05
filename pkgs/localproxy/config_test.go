package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestValidateDuration(t *testing.T) {
	for _, value := range []string{"1", "250ms", "2s", "3m", "4h", "5d", "0"} {
		if err := validateDuration(value, "duration"); err != nil {
			t.Fatalf("expected %q to be valid: %v", value, err)
		}
	}
	for _, value := range []string{"", "-1", "-1s", "1w", "abc", "ms"} {
		if err := validateDuration(value, "duration"); err == nil {
			t.Fatalf("expected %q to be invalid", value)
		}
	}
}

func TestDefaultLimitsPreferWebEnv(t *testing.T) {
	t.Setenv("LOCALPROXY_WEB_DEFAULT_MAX_BACKEND_CONNS", "77")
	t.Setenv("LOCALPROXY_HTTP_DEFAULT_MAX_BACKEND_CONNS", "55")
	limits, err := defaultLimits()
	if err != nil {
		t.Fatal(err)
	}
	if limits.MaxBackendConns != 77 {
		t.Fatalf("expected web env value, got %d", limits.MaxBackendConns)
	}
}

func TestDefaultLimitsFallbackToHTTPEnv(t *testing.T) {
	t.Setenv("LOCALPROXY_WEB_DEFAULT_MAX_BACKEND_CONNS", "")
	t.Setenv("LOCALPROXY_HTTP_DEFAULT_MAX_BACKEND_CONNS", "55")
	limits, err := defaultLimits()
	if err != nil {
		t.Fatal(err)
	}
	if limits.MaxBackendConns != 55 {
		t.Fatalf("expected http env fallback, got %d", limits.MaxBackendConns)
	}
}

func TestDefaultCertPathUsesXDGConfigHome(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	want := filepath.Join(dir, "localproxy", "localproxy.pem")
	if got := defaultCertPath(); got != want {
		t.Fatalf("defaultCertPath() = %q, want %q", got, want)
	}
}

func TestStateRoundTrip(t *testing.T) {
	dir := t.TempDir()
	cfg := Config{
		Host:           "devbox",
		BindAddr:       "127.0.0.1",
		StateDir:       dir,
		HTTP3Policy:    "auto",
		HTTP3Effective: true,
		FrontendALPN:   "h2,http/1.1",
		Ports: []PortSpec{{
			Port:             5173,
			Mode:             ModeWeb,
			Client:           ClientHTTP,
			BackendPolicy:    BackendHTTPS,
			BackendEffective: BackendHTTPS,
		}},
		Limits: Limits{MaxTotalConns: 1000, MaxBackendConns: 32},
	}
	if err := saveState(cfg); err != nil {
		t.Fatal(err)
	}
	loaded, err := loadState(dir)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Host != cfg.Host || loaded.Ports[0].BackendEffective != BackendHTTPS {
		t.Fatalf("unexpected loaded state: %#v", loaded)
	}
	if _, err := os.Stat(statePath(dir)); err != nil {
		t.Fatal(err)
	}
}
