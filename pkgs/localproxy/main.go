package main

import (
	"errors"
	"fmt"
	"os"
	"strings"
)

type exitError struct {
	code int
	msg  string
}

func (e exitError) Error() string {
	return e.msg
}

func usageErrorf(format string, args ...any) error {
	return exitError{code: 64, msg: fmt.Sprintf(format, args...)}
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		var ee exitError
		if errors.As(err, &ee) {
			fmt.Fprintf(os.Stderr, "localproxy: %s\n", ee.msg)
			os.Exit(ee.code)
		}
		fmt.Fprintf(os.Stderr, "localproxy: %s\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		usage()
		return exitError{code: 64, msg: "missing command"}
	}

	if len(args) == 1 && args[0] == "status" {
		return statusAll()
	}

	if args[0] == "http" || args[0] == "https" {
		return usageErrorf("%s mode was removed; use localproxy <host> enable --port ...", args[0])
	}

	if len(args) < 2 {
		usage()
		return exitError{code: 64, msg: "missing action"}
	}

	host := args[0]
	if err := validateHost(host); err != nil {
		return err
	}
	action := args[1]
	rest := args[2:]

	switch action {
	case "enable":
		return enable(host, rest)
	case "disable":
		if len(rest) != 0 {
			return usageErrorf("disable does not accept arguments")
		}
		return disable(host)
	case "status":
		if len(rest) != 0 {
			return usageErrorf("status does not accept arguments")
		}
		return statusOne(host)
	default:
		usage()
		return usageErrorf("unknown action: %s", action)
	}
}

func enable(host string, args []string) error {
	cleanupLegacyHost(host)
	cfg, err := parseEnableConfig(host, args)
	if err != nil {
		return err
	}
	cfg, err = finalizeEnableConfig(cfg)
	if err != nil {
		return err
	}
	if err := enableHAProxy(cfg); err != nil {
		return err
	}
	fmt.Printf("enabled %s on %s for port(s): %s\n", host, cfg.BindAddr, strings.Join(enabledPortSummaries(cfg.Ports), " "))
	return nil
}

func disable(host string) error {
	stopAndRemoveDir(hostDir(host))
	cleanupLegacyHost(host)
	fmt.Printf("disabled %s\n", host)
	return nil
}

func enabledPortSummaries(specs []PortSpec) []string {
	out := make([]string, 0, len(specs))
	for _, spec := range specs {
		spec = normalizePortSpec(spec)
		if spec.Mode == ModeTCP {
			if spec.TargetPort == spec.ListenPort {
				out = append(out, fmt.Sprintf("%d[tcp]", spec.ListenPort))
			} else {
				out = append(out, fmt.Sprintf("%d[tcp->%d]", spec.ListenPort, spec.TargetPort))
			}
		} else {
			out = append(out, fmt.Sprintf("%d[client=%s,backend=%s,effective=%s]", spec.Port, spec.Client, spec.BackendPolicy, spec.BackendEffective))
		}
	}
	return out
}

func usage() {
	fmt.Fprint(os.Stderr, `usage:
  localproxy <host> enable [options] --port SPEC [--port SPEC...]
  localproxy <host> enable [options] <tcp-port> [tcp-port...]
  localproxy <host> disable
  localproxy <host> status
  localproxy status

port specs:
  --port 22:tcp
  --port 2222:tcp,target=22
  --port 5173:client=http,backend=https
  --port 3000:client=http,backend=http
  --port 9000:client=https,backend=http

TCP target defaults to the listen port when omitted.

options:
  --max-total-conns N
  --max-sessions-per-second N
  --max-backend-conns N
  --max-idle-backend-conns N
  --queue-timeout DURATION
  --http-keepalive-timeout DURATION
  --tunnel-timeout DURATION
  --frontend-cert PEM
  --http3 auto|on|off
  --frontend-alpn h2,http/1.1|http/1.1
`)
}
