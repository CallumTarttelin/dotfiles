package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"time"
)

func ensureFrontendCert(path string, bindAddr string) (string, error) {
	if path != "" {
		path = expandHome(path)
		info, err := os.Stat(path)
		if err != nil {
			return "", usageErrorf("--frontend-cert is not readable: %s", path)
		}
		if info.IsDir() {
			return "", usageErrorf("--frontend-cert is a directory: %s", path)
		}
		file, err := os.Open(path)
		if err != nil {
			return "", usageErrorf("--frontend-cert is not readable: %s", path)
		}
		_ = file.Close()
		return path, nil
	}

	path = defaultCertPath()
	if _, err := os.Stat(path); err == nil {
		return path, nil
	} else if !os.IsNotExist(err) {
		return "", fmt.Errorf("stat default cert: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", fmt.Errorf("create cert directory: %w", err)
	}

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return "", fmt.Errorf("generate private key: %w", err)
	}

	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return "", fmt.Errorf("generate serial: %w", err)
	}

	template := x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName: "localproxy",
		},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		DNSNames:              []string{"localhost"},
		IPAddresses: []net.IP{
			net.ParseIP("127.0.0.1"),
			net.ParseIP("::1"),
		},
	}
	if ip := net.ParseIP(bindAddr); ip != nil {
		already := false
		for _, existing := range template.IPAddresses {
			if existing.Equal(ip) {
				already = true
				break
			}
		}
		if !already {
			template.IPAddresses = append(template.IPAddresses, ip)
		}
	}

	certDER, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if err != nil {
		return "", fmt.Errorf("create certificate: %w", err)
	}

	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		if os.IsExist(err) {
			return path, nil
		}
		return "", fmt.Errorf("create certificate file: %w", err)
	}
	defer file.Close()

	if err := pem.Encode(file, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)}); err != nil {
		return "", fmt.Errorf("write private key: %w", err)
	}
	if err := pem.Encode(file, &pem.Block{Type: "CERTIFICATE", Bytes: certDER}); err != nil {
		return "", fmt.Errorf("write certificate: %w", err)
	}
	return path, nil
}
