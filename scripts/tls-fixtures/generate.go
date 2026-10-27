package main

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func generateFixtures(directory string) error {
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	rootKey, err := rsa.GenerateKey(rand.Reader, 3072)
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	root := authority("shared", now)
	rootDER, err := x509.CreateCertificate(rand.Reader, root, root, rootKey.Public(), rootKey)
	if err != nil {
		return err
	}
	if err := writePEM(filepath.Join(directory, "root.pem"), "CERTIFICATE", rootDER); err != nil {
		return err
	}
	for index, name := range fixtureNames[1:] {
		// The matrix is fixed test material, never operator-supplied key policy.
		bits := 2048
		if strings.HasSuffix(name, "1024") {
			bits = 1024
		}
		if strings.HasSuffix(name, "2047") {
			bits = 2047
		}
		issuer, signer := root, crypto.Signer(rootKey)
		if strings.HasPrefix(name, "root") || name == "untrusted" {
			issuer = authority(name, now)
			rootBits := bits
			if name == "untrusted" {
				rootBits = 3072
			}
			signer, err = rsa.GenerateKey(rand.Reader, rootBits)
			if err != nil {
				return err
			}
			der, err := x509.CreateCertificate(rand.Reader, issuer, issuer, signer.Public(), signer)
			if err != nil {
				return err
			}
			if name != "untrusted" {
				if err := writePEM(filepath.Join(directory, "anchor-"+name+".pem"), "CERTIFICATE", der); err != nil {
					return err
				}
			}
		}
		var chain [][]byte
		if strings.HasPrefix(name, "intermediate") {
			key, err := rsa.GenerateKey(rand.Reader, bits)
			if err != nil {
				return err
			}
			intermediate := authority(name, now)
			der, err := x509.CreateCertificate(rand.Reader, intermediate, issuer, key.Public(), signer)
			if err != nil {
				return err
			}
			chain = append(chain, der)
			issuer, signer = intermediate, key
		}
		var key crypto.Signer
		if strings.HasPrefix(name, "rsa") || strings.HasPrefix(name, "trusted") {
			key, err = rsa.GenerateKey(rand.Reader, bits)
		} else {
			curve := elliptic.P256()
			if name == "p384" {
				curve = elliptic.P384()
			}
			if name == "p521" {
				curve = elliptic.P521()
			}
			key, err = ecdsa.GenerateKey(curve, rand.Reader)
		}
		if err != nil {
			return err
		}
		leaf := &x509.Certificate{SerialNumber: big.NewInt(int64(index + 10)), Subject: pkix.Name{CommonName: fixtureHost},
			DNSNames: []string{fixtureHost}, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(7 * 24 * time.Hour),
			BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
		if _, ok := key.(*rsa.PrivateKey); ok {
			leaf.KeyUsage |= x509.KeyUsageKeyEncipherment
		}
		if name == "wronghost" {
			leaf.DNSNames = []string{"other.invalid"}
		}
		if name == "expired" {
			leaf.NotBefore = now.Add(-3 * time.Hour)
			leaf.NotAfter = now.Add(-2 * time.Hour)
		}
		if strings.HasPrefix(name, "trusted") {
			issuer, signer = leaf, key
		}
		der, err := x509.CreateCertificate(rand.Reader, leaf, issuer, key.Public(), signer)
		if err != nil {
			return err
		}
		if strings.HasPrefix(name, "trusted") {
			if err := writePEM(filepath.Join(directory, "anchor-"+name+".pem"), "CERTIFICATE", der); err != nil {
				return err
			}
		}
		certificate := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
		for _, der := range chain {
			certificate = append(certificate, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})...)
		}
		if err := os.WriteFile(filepath.Join(directory, name+"-cert.pem"), certificate, 0644); err != nil {
			return err
		}
		private, err := x509.MarshalPKCS8PrivateKey(key)
		if err != nil {
			return err
		}
		if err := writePEM(filepath.Join(directory, name+"-key.pem"), "PRIVATE KEY", private); err != nil {
			return err
		}
	}
	return generateCertificateOnly(directory, root, rootKey, now)
}

// Certificates served for inspection only. They get no listener and no private
// key: the client key policy must refuse a key type it cannot measure, which
// does not depend on whether the platform ever negotiates that type.
func generateCertificateOnly(directory string, root *x509.Certificate, rootKey crypto.Signer, now time.Time) error {
	for index, name := range certificateOnlyNames {
		public, _, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			return err
		}
		leaf := &x509.Certificate{SerialNumber: big.NewInt(int64(index + 90)), Subject: pkix.Name{CommonName: fixtureHost},
			DNSNames: []string{fixtureHost}, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(7 * 24 * time.Hour),
			BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
		der, err := x509.CreateCertificate(rand.Reader, leaf, root, public, rootKey)
		if err != nil {
			return err
		}
		if err := writePEM(filepath.Join(directory, name+"-cert.pem"), "CERTIFICATE", der); err != nil {
			return err
		}
	}
	return nil
}

func authority(name string, now time.Time) *x509.Certificate {
	return &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "KyAuth disposable TLS fixture " + name + " root"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(365 * 24 * time.Hour), BasicConstraintsValid: true, IsCA: true,
		KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageCRLSign}
}

func writePEM(path, kind string, der []byte) error {
	mode := os.FileMode(0644)
	if kind == "PRIVATE KEY" {
		mode = 0600
	}
	return os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: kind, Bytes: der}), mode)
}
