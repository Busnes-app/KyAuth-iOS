package main

import (
	"context"
	"crypto/ecdsa"
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
	anchors, err := filepath.Glob(filepath.Join(dir, "anchor-*.pem"))
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range anchors {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if !pool.AppendCertsFromPEM(data) {
			t.Fatal("invalid fixture anchor", path)
		}
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
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, ServerName: hostname, MinVersion: tls.VersionTLS10},
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "tcp", target.listener.Addr().String())
		}}
	t.Cleanup(transport.CloseIdleConnections)
	return &http.Client{Transport: transport}
}

func TestFixtureCalibrationAndConnectionReuse(t *testing.T) {
	fixtures, roots := startTestFixtures(t)
	for _, name := range fixtureNames[1:] {
		if name == "expired" || name == "wronghost" || name == "untrusted" {
			continue
		}
		t.Run(name, func(t *testing.T) {
			f := fixtures[name]
			certificate, err := x509.ParseCertificate(f.leaf)
			if err != nil {
				t.Fatal(err)
			}
			client := fixtureClient(t, f, roots, fixtureHost)
			for range 2 {
				response, err := client.Post("https://"+fixtureHost+"/probe", "application/json", strings.NewReader(`{"public":"canary"}`))
				if err != nil {
					t.Fatal(err)
				}
				target := certificate
				if strings.HasPrefix(name, "root") {
					chain := response.TLS.VerifiedChains[0]
					target = chain[len(chain)-1]
					if len(response.TLS.PeerCertificates) != 1 {
						t.Fatal("server must omit its root")
					}
				}
				if strings.HasPrefix(name, "intermediate") {
					if len(response.TLS.PeerCertificates) != 2 {
						t.Fatal("missing intermediate")
					}
					target = response.TLS.PeerCertificates[1]
				}
				rsaBits := map[string]int{"rsa1024": 1024, "rsa2047": 2047, "rsa2048": 2048,
					"root1024": 1024, "root2047": 2047, "intermediate1024": 1024, "intermediate2047": 2047,
					"trusted1024": 1024, "trusted2047": 2047, "trusted2048": 2048}
				if bits, ok := rsaBits[name]; ok {
					key, ok := target.PublicKey.(*rsa.PublicKey)
					if !ok || key.N.BitLen() != bits {
						t.Fatal("wrong literal RSA fixture modulus", name)
					}
				} else {
					bits := 256
					if name == "p384" {
						bits = 384
					}
					if name == "p521" {
						bits = 521
					}
					key, ok := target.PublicKey.(*ecdsa.PublicKey)
					if !ok || key.Curve.Params().BitSize != bits {
						t.Fatal("wrong EC fixture", name)
					}
				}
				versions := map[string]uint16{"tls10": tls.VersionTLS10, "tls11": tls.VersionTLS11, "tls12": tls.VersionTLS12, "tls13": tls.VersionTLS13}
				if version, ok := versions[name]; ok && response.TLS.Version != version {
					t.Fatal("wrong negotiated fixture version", name)
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

func TestInvalidCertificateFixturesReceiveNoApplicationBytes(t *testing.T) {
	fixtures, roots := startTestFixtures(t)
	for _, name := range []string{"wronghost", "expired", "untrusted"} {
		t.Run(name, func(t *testing.T) {
			f := fixtures[name]
			response, err := fixtureClient(t, f, roots, fixtureHost).Get("https://" + fixtureHost + "/probe")
			if err == nil {
				_ = response.Body.Close()
				t.Fatal("invalid certificate accepted", name)
			}
			if f.counts.connections.Load() == 0 || f.counts.bytes.Load() != 0 || f.counts.requests.Load() != 0 {
				t.Fatal("invalid fixture accounting", name)
			}
		})
	}
}
