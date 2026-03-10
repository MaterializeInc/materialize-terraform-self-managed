package helpers

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"testing"
	"time"
)

// ValidateDNSResolution checks that a hostname resolves to the expected IP address
func ValidateDNSResolution(t *testing.T, hostname, expectedIP string) {
	t.Helper()

	resolver := &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			d := net.Dialer{Timeout: 10 * time.Second}
			return d.DialContext(ctx, "udp", "8.8.8.8:53")
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	ips, err := resolver.LookupHost(ctx, hostname)
	if err != nil {
		t.Fatalf("DNS resolution failed for %s: %v", hostname, err)
	}

	found := false
	for _, ip := range ips {
		if ip == expectedIP {
			found = true
			break
		}
	}

	if !found {
		t.Fatalf("DNS resolution for %s returned %v, expected to contain %s", hostname, ips, expectedIP)
	}

	t.Logf("DNS resolution OK: %s -> %s", hostname, expectedIP)
}

// ValidateTLSCertificate connects to hostname:port with TLS and verifies the certificate
func ValidateTLSCertificate(t *testing.T, hostname string, port int) {
	t.Helper()

	addr := fmt.Sprintf("%s:%d", hostname, port)
	conn, err := tls.DialWithDialer(
		&net.Dialer{Timeout: 30 * time.Second},
		"tcp",
		addr,
		&tls.Config{
			ServerName: hostname,
		},
	)
	if err != nil {
		t.Fatalf("TLS connection to %s failed: %v", addr, err)
	}
	defer conn.Close()

	state := conn.ConnectionState()
	if len(state.PeerCertificates) == 0 {
		t.Fatalf("No TLS certificates returned from %s", addr)
	}

	cert := state.PeerCertificates[0]
	err = cert.VerifyHostname(hostname)
	if err != nil {
		t.Fatalf("TLS certificate for %s does not match hostname: %v (SANs: %v)", addr, err, cert.DNSNames)
	}

	t.Logf("TLS certificate OK: %s (SANs: %v, Issuer: %s)", addr, cert.DNSNames, cert.Issuer.CommonName)
}

// ValidateHTTPS performs an HTTPS GET request and checks for a successful response
func ValidateHTTPS(t *testing.T, url string) {
	t.Helper()

	client := &http.Client{
		Timeout: 30 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{},
		},
	}

	resp, err := client.Get(url)
	if err != nil {
		t.Fatalf("HTTPS request to %s failed: %v", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 400 {
		t.Fatalf("HTTPS request to %s returned status %d", url, resp.StatusCode)
	}

	t.Logf("HTTPS OK: %s -> %d", url, resp.StatusCode)
}
