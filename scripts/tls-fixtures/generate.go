package main

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
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
	root := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "KyAuth disposable TLS fixture root"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(365 * 24 * time.Hour),
		BasicConstraintsValid: true, IsCA: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageCRLSign}
	der, err := x509.CreateCertificate(rand.Reader, root, root, rootKey.Public(), rootKey)
	if err != nil {
		return err
	}
	if err := writePEM(filepath.Join(directory, "root.pem"), "CERTIFICATE", der); err != nil {
		return err
	}
	for index, name := range fixtureNames[1:] {
		var key crypto.Signer
		switch name {
		case "rsa2048":
			key, err = rsa.GenerateKey(rand.Reader, 2048)
		case "rsa2047":
			key, err = rsa.GenerateKey(rand.Reader, 2047)
		case "p256":
			key, err = ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		default:
			return fmt.Errorf("unknown fixture %s", name)
		}
		if err != nil {
			return err
		}
		leaf := &x509.Certificate{SerialNumber: big.NewInt(int64(index + 2)), Subject: pkix.Name{CommonName: fixtureHost},
			DNSNames: []string{fixtureHost}, NotBefore: root.NotBefore, NotAfter: now.Add(7 * 24 * time.Hour),
			BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature,
			ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
		if _, ok := key.(*rsa.PrivateKey); ok {
			leaf.KeyUsage |= x509.KeyUsageKeyEncipherment
		}
		der, err := x509.CreateCertificate(rand.Reader, leaf, root, key.Public(), rootKey)
		if err != nil {
			return err
		}
		if err := writePEM(filepath.Join(directory, name+"-cert.pem"), "CERTIFICATE", der); err != nil {
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
	return nil
}

func writePEM(path, kind string, der []byte) error {
	mode := os.FileMode(0644)
	if kind == "PRIVATE KEY" {
		mode = 0600
	}
	return os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: kind, Bytes: der}), mode)
}
