// Loopback-only public TLS fixtures for the native simulator test suite.
package main

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

const fixtureHost = "kyauth-tls-test.invalid"

var fixtureNames = []string{
	"control", "rsa2048", "rsa2047", "p256", "rsa1024", "p384", "p521",
	"intermediate1024", "intermediate2047", "root1024", "root2047",
	"trusted1024", "trusted2047", "trusted2048", "wronghost", "expired", "untrusted",
	"tls10", "tls11", "tls12", "tls13",
}

type counters struct {
	bytes       atomic.Uint64
	requests    atomic.Uint64
	connections atomic.Uint64
}

type countingConn struct {
	net.Conn
	counts *counters
}

func (c countingConn) Read(p []byte) (int, error) {
	n, err := c.Conn.Read(p) // TLS has already decrypted these application bytes.
	c.counts.bytes.Add(uint64(n))
	return n, err
}

type fixtureListener struct {
	net.Listener
	config *tls.Config
	counts *counters
}

func (l fixtureListener) Accept() (net.Conn, error) {
	conn, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	l.counts.connections.Add(1)
	return countingConn{Conn: tls.Server(conn, l.config), counts: l.counts}, nil
}

type fixture struct {
	server   *http.Server
	listener net.Listener
	counts   *counters
	leaf     []byte
}

func loadFixtures(directory string, basePort int) (map[string]*fixture, error) {
	fixtures := make(map[string]*fixture)
	defer func() {
		// A partial bind must not leave earlier listeners behind.
		if len(fixtures) != len(fixtureNames) {
			for _, f := range fixtures {
				_ = f.listener.Close()
			}
		}
	}()
	for index, name := range fixtureNames {
		certificate := name
		if name == "control" {
			certificate = "rsa2048"
		}
		key, err := tls.LoadX509KeyPair(filepath.Join(directory, certificate+"-cert.pem"), filepath.Join(directory, certificate+"-key.pem"))
		if err != nil {
			return nil, err
		}
		port := 0
		if basePort != 0 {
			port = basePort + index
		}
		listener, err := net.Listen("tcp4", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)))
		if err != nil {
			return nil, err
		}
		counts := &counters{}
		minimum, maximum := uint16(tls.VersionTLS12), uint16(0)
		switch name {
		case "tls10":
			minimum, maximum = tls.VersionTLS10, tls.VersionTLS10
		case "tls11":
			minimum, maximum = tls.VersionTLS11, tls.VersionTLS11
		case "tls12":
			minimum, maximum = tls.VersionTLS12, tls.VersionTLS12
		case "tls13":
			minimum, maximum = tls.VersionTLS13, tls.VersionTLS13
		}
		f := &fixture{listener: fixtureListener{Listener: listener, counts: counts, config: &tls.Config{
			Certificates: []tls.Certificate{key}, MinVersion: minimum, MaxVersion: maximum, NextProtos: []string{"http/1.1"},
		}}, counts: counts, leaf: key.Certificate[0]}
		f.server = &http.Server{ReadHeaderTimeout: 3 * time.Second, ReadTimeout: 5 * time.Second,
			WriteTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second}
		fixtures[name] = f
	}
	// The map is complete before any server starts. Each peer owns its counters.
	for _, f := range fixtures {
		f.server.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			f.counts.requests.Add(1)
			if _, err := io.Copy(io.Discard, http.MaxBytesReader(w, r.Body, 64*1024)); err != nil {
				http.Error(w, "fixture request exceeds limit", http.StatusRequestEntityTooLarge)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			var result any = map[string]bool{"ok": true}
			switch {
			case r.URL.Path == "/cases":
				cases := make([]map[string]any, 0, len(fixtureNames)-1)
				for _, name := range fixtureNames[1:] {
					cases = append(cases, map[string]any{"name": name, "port": fixtures[name].listener.Addr().(*net.TCPAddr).Port})
				}
				result = cases
			case r.URL.Path == "/stats":
				stats := make(map[string]map[string]uint64)
				for name, peer := range fixtures {
					stats[name] = map[string]uint64{"bytes": peer.counts.bytes.Load(), "requests": peer.counts.requests.Load(), "connections": peer.counts.connections.Load()}
				}
				result = stats
			case strings.HasPrefix(r.URL.Path, "/certificate/"):
				peer, ok := fixtures[strings.TrimPrefix(r.URL.Path, "/certificate/")]
				if !ok {
					http.NotFound(w, r)
					return
				}
				result = map[string]string{"certificate": base64.StdEncoding.EncodeToString(peer.leaf)}
			case r.URL.Path == "/redirect":
				port := fixtures["rsa2048"].listener.Addr().(*net.TCPAddr).Port
				w.Header().Set("Location", "https://"+net.JoinHostPort(fixtureHost, strconv.Itoa(port))+"/redirect-target")
				w.WriteHeader(http.StatusFound)
			}
			if err := json.NewEncoder(w).Encode(result); err != nil {
				return // The client closed; headers/bodies are never logged.
			}
		})
	}
	return fixtures, nil
}

func run(directory string, basePort int) error {
	fixtures, err := loadFixtures(directory, basePort)
	if err != nil {
		return err
	}
	defer func() {
		for _, f := range fixtures {
			_ = f.server.Close()
			_ = f.listener.Close()
		}
	}()
	failures := make(chan error, len(fixtures))
	for name, f := range fixtures {
		fmt.Println("public TLS fixture", name, f.listener.Addr())
		go func() {
			if err := f.server.Serve(f.listener); !errors.Is(err, http.ErrServerClosed) {
				failures <- err
			}
		}()
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	select {
	case <-ctx.Done():
		return nil
	case err := <-failures:
		return err
	}
}

func main() {
	directory := flag.String("certificates", "certificates", "directory containing public fixture certificates and keys")
	generate := flag.Bool("generate", false, "replace public fixtures; CA private key is never stored")
	port := flag.Int("base-port", 46100, "first loopback port; zero selects ephemeral ports")
	flag.Parse()
	if flag.NArg() != 0 || *port < 0 || *port > 65535-len(fixtureNames)+1 {
		fmt.Fprintln(os.Stderr, "invalid fixture arguments")
		os.Exit(2)
	}
	var err error
	if *generate {
		err = generateFixtures(*directory)
	} else {
		err = run(*directory, *port)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
