package handlers

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// helper to generate x509 cert/key in memory for testing
func generateTestCert(commonName string, parent *x509.Certificate, parentKey *rsa.PrivateKey, isCA bool) ([]byte, []byte, *x509.Certificate, *rsa.PrivateKey, error) {
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, nil, nil, nil, err
	}

	serialNumberLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serialNumber, err := rand.Int(rand.Reader, serialNumberLimit)
	if err != nil {
		return nil, nil, nil, nil, err
	}

	template := x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			CommonName: commonName,
		},
		NotBefore:             time.Now().Add(-1 * time.Hour),
		NotAfter:              time.Now().Add(1 * time.Hour),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
		BasicConstraintsValid: true,
	}

	if isCA {
		template.IsCA = true
		template.KeyUsage |= x509.KeyUsageCertSign
	} else {
		template.DNSNames = []string{commonName, "localhost"}
		template.IPAddresses = []net.IP{net.ParseIP("127.0.0.1")}
	}

	var derBytes []byte
	if parent == nil {
		// Self-signed (CA)
		derBytes, err = x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	} else {
		derBytes, err = x509.CreateCertificate(rand.Reader, &template, parent, &priv.PublicKey, parentKey)
	}
	if err != nil {
		return nil, nil, nil, nil, err
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: derBytes})

	privBytes, err := x509.MarshalPKCS8PrivateKey(priv)
	if err != nil {
		return nil, nil, nil, nil, err
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: privBytes})

	parsedCert, err := x509.ParseCertificate(derBytes)
	if err != nil {
		return nil, nil, nil, nil, err
	}

	return certPEM, keyPEM, parsedCert, priv, nil
}

func TestMTLSSecurityBoundaries(t *testing.T) {
	// 1. Generate local root CA
	caCertPEM, _, caCert, caKey, err := generateTestCert("Test-CA", nil, nil, true)
	if err != nil {
		t.Fatalf("Failed to generate CA: %v", err)
	}

	// 2. Generate server cert signed by CA
	serverCertPEM, serverKeyPEM, _, _, err := generateTestCert("auth-service", caCert, caKey, false)
	if err != nil {
		t.Fatalf("Failed to generate server cert: %v", err)
	}

	// 3. Generate valid client cert signed by CA
	clientCertPEM, clientKeyPEM, _, _, err := generateTestCert("api-gateway", caCert, caKey, false)
	if err != nil {
		t.Fatalf("Failed to generate client cert: %v", err)
	}

	// 4. Generate untrusted root CA
	_, _, untrustedCACert, untrustedCAKey, err := generateTestCert("Untrusted-CA", nil, nil, true)
	if err != nil {
		t.Fatalf("Failed to generate untrusted CA: %v", err)
	}

	// 5. Generate client cert signed by untrusted CA
	untrustedClientCertPEM, untrustedClientKeyPEM, _, _, err := generateTestCert("malicious-service", untrustedCACert, untrustedCAKey, false)
	if err != nil {
		t.Fatalf("Failed to generate untrusted client cert: %v", err)
	}

	// Set up server TLS Config (Require and verify client certificate)
	serverKeyPair, err := tls.X509KeyPair(serverCertPEM, serverKeyPEM)
	if err != nil {
		t.Fatalf("Failed to load server key pair: %v", err)
	}
	serverCAPool := x509.NewCertPool()
	serverCAPool.AppendCertsFromPEM(caCertPEM)

	serverTLSConfig := &tls.Config{
		Certificates: []tls.Certificate{serverKeyPair},
		ClientAuth:   tls.RequireAndVerifyClientCert,
		ClientCAs:    serverCAPool,
		MinVersion:   tls.VersionTLS12,
	}

	// Start httptest TLS server
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("success"))
	})
	ts := httptest.NewUnstartedServer(handler)
	ts.TLS = serverTLSConfig
	ts.StartTLS()
	defer ts.Close()

	// Helper to create client with custom TLS settings
	makeClient := func(clientCertPEM, clientKeyPEM, caCertPEM []byte) (*http.Client, error) {
		tlsConfig := &tls.Config{
			MinVersion: tls.VersionTLS12,
		}
		if clientCertPEM != nil && clientKeyPEM != nil {
			clientKeyPair, err := tls.X509KeyPair(clientCertPEM, clientKeyPEM)
			if err != nil {
				return nil, err
			}
			tlsConfig.Certificates = []tls.Certificate{clientKeyPair}
		}
		if caCertPEM != nil {
			clientCAPool := x509.NewCertPool()
			clientCAPool.AppendCertsFromPEM(caCertPEM)
			tlsConfig.RootCAs = clientCAPool
		}
		return &http.Client{
			Transport: &http.Transport{
				TLSClientConfig: tlsConfig,
			},
		}, nil
	}

	// CASE A: Request without client certificate -> must fail
	t.Run("NoClientCertReject", func(t *testing.T) {
		client, err := makeClient(nil, nil, caCertPEM)
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}
		_, err = client.Get(ts.URL)
		if err == nil {
			t.Error("Expected connection failure when request has no client certificate, but succeeded")
		} else {
			t.Logf("Successfully rejected without client cert: %v", err)
		}
	})

	// CASE B: Request with cert signed by untrusted CA -> must fail
	t.Run("UntrustedClientCertReject", func(t *testing.T) {
		client, err := makeClient(untrustedClientCertPEM, untrustedClientKeyPEM, caCertPEM)
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}
		_, err = client.Get(ts.URL)
		if err == nil {
			t.Error("Expected connection failure when request has untrusted client certificate, but succeeded")
		} else {
			t.Logf("Successfully rejected untrusted client cert: %v", err)
		}
	})

	// CASE C: Request with correct cert signed by local root CA -> must succeed
	t.Run("TrustedClientCertSuccess", func(t *testing.T) {
		client, err := makeClient(clientCertPEM, clientKeyPEM, caCertPEM)
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}
		resp, err := client.Get(ts.URL)
		if err != nil {
			t.Fatalf("Expected connection success with correct client certificate, but failed: %v", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}
	})
}
