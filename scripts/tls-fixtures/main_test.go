package main

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func startTestFixtures(t *testing.T) (map[string]*fixture, *x509.CertPool) {
	t.Helper()
	dir := t.TempDir()
	if err := generateFixtures(dir); err != nil {
		t.Fatal(err)
	}
	root, err := os.ReadFile(filepath.Join(dir, "root.pem"))
	if err != nil {
		t.Fatal(err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(root) {
		t.Fatal("fixture root is not a certificate")
	}
	block, _ := pem.Decode(root)
	certificate, err := x509.ParseCertificate(block.Bytes)
	if err != nil || !certificate.IsCA || certificate.PublicKey.(*rsa.PublicKey).N.BitLen() != 3072 {
		t.Fatal("fixture root must be an RSA-3072 CA", err)
	}
	fixtures, err := loadFixtures(dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range fixtures {
		t.Cleanup(func() { _ = f.server.Close() })
		go func() { _ = f.server.Serve(f.listener) }()
	}
	return fixtures, pool
}

func fixtureClient(t *testing.T, target *fixture, roots *x509.CertPool, hostname string) *http.Client {
	t.Helper()
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, ServerName: hostname},
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "tcp", target.listener.Addr().String())
		}}
	t.Cleanup(transport.CloseIdleConnections)
	return &http.Client{Transport: transport}
}

func TestFixtureCalibrationAndConnectionReuse(t *testing.T) {
	fixtures, roots := startTestFixtures(t)
	for _, name := range []string{"rsa2048", "rsa2047", "p256"} {
		t.Run(name, func(t *testing.T) {
			f := fixtures[name]
			certificate, err := x509.ParseCertificate(f.leaf)
			if err != nil {
				t.Fatal(err)
			}
			if key, ok := certificate.PublicKey.(*rsa.PublicKey); ok {
				bits := 2048
				if name == "rsa2047" {
					bits = 2047
				}
				if key.N.BitLen() != bits {
					t.Fatal("fixture modulus was rounded", key.N.BitLen())
				}
			}
			client := fixtureClient(t, f, roots, fixtureHost)
			for range 2 {
				response, err := client.Post("https://"+fixtureHost+"/probe", "application/json", strings.NewReader(`{"public":"canary"}`))
				if err != nil {
					t.Fatal(err)
				}
				data, err := io.ReadAll(response.Body)
				if closeErr := response.Body.Close(); closeErr != nil {
					t.Fatal(closeErr)
				}
				if err != nil || response.StatusCode != http.StatusOK || !strings.Contains(string(data), `"ok":true`) {
					t.Fatal("fixture did not serve the canary", err)
				}
			}
			if f.counts.bytes.Load() == 0 || f.counts.requests.Load() != 2 || f.counts.connections.Load() != 1 {
				t.Fatalf("fixture accounting/reuse failed: bytes=%d requests=%d connections=%d", f.counts.bytes.Load(), f.counts.requests.Load(), f.counts.connections.Load())
			}
		})
	}
}

func TestTrustFailuresReceiveNoApplicationBytes(t *testing.T) {
	for _, invalid := range []string{"untrusted-root", "wrong-hostname"} {
		t.Run(invalid, func(t *testing.T) {
			fixtures, roots := startTestFixtures(t)
			f := fixtures["rsa2048"]
			host := fixtureHost
			if invalid == "untrusted-root" {
				roots = x509.NewCertPool()
			} else {
				host = "other.invalid"
			}
			response, err := fixtureClient(t, f, roots, host).Post("https://"+fixtureHost+"/probe", "application/json", strings.NewReader(`{"public":"canary"}`))
			if err == nil {
				_ = response.Body.Close()
				t.Fatal("invalid trust control succeeded")
			}
			if f.counts.bytes.Load() != 0 || f.counts.requests.Load() != 0 {
				t.Fatal("untrusted TLS peer received HTTP data")
			}
		})
	}
}
