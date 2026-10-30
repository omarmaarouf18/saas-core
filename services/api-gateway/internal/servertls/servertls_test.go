package servertls

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// writeCert writes a PEM cert/key pair for dnsNames, signed by parent (or
// self-signed when parent is nil), and returns the paths and the cert.
func writeCert(t *testing.T, dir, name string, dnsNames []string, isCA bool, parent *x509.Certificate, parentKey *ecdsa.PrivateKey) (string, string, *x509.Certificate, *ecdsa.PrivateKey) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(time.Now().UnixNano()),
		Subject:               pkix.Name{CommonName: name},
		DNSNames:              dnsNames,
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1")},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  isCA,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
	}
	signer, signerKey := tmpl, key
	if parent != nil {
		signer, signerKey = parent, parentKey
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, signer, &key.PublicKey, signerKey)
	if err != nil {
		t.Fatal(err)
	}
	cert, _ := x509.ParseCertificate(der)
	keyDER, _ := x509.MarshalECPrivateKey(key)
	certPath, keyPath := filepath.Join(dir, name+".crt"), filepath.Join(dir, name+".key")
	_ = os.WriteFile(certPath, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600)
	_ = os.WriteFile(keyPath, pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}), 0o600)
	return certPath, keyPath, cert, key
}

// TestServerTLSConfig_InternalSNIGetsInternalCert pins that saas-net callers
// dialling https://api-gateway can verify the gateway against the internal
// CA (needed for the console's /admin/version and auth-service's
// /admin/internal/audit calls), while other SNIs keep the external cert.
func TestServerTLSConfig_InternalSNIGetsInternalCert(t *testing.T) {
	dir := t.TempDir()
	_, _, caCert, caKey := writeCert(t, dir, "ca", nil, true, nil, nil)
	intCert, intKey, _, _ := writeCert(t, dir, "api-gateway", []string{"api-gateway"}, false, caCert, caKey)
	extCert, extKey, _, _ := writeCert(t, dir, "external", []string{"localhost"}, false, nil, nil)

	cfg, err := Config(extCert, extKey, intCert, intKey, "")
	if err != nil {
		t.Fatalf("Config: %v", err)
	}
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))
	srv.TLS = cfg
	srv.StartTLS()
	defer srv.Close()
	addr := srv.Listener.Addr().String()

	pool := x509.NewCertPool()
	pool.AddCert(caCert)
	conn, err := tls.Dial("tcp", addr, &tls.Config{RootCAs: pool, ServerName: "api-gateway", MinVersion: tls.VersionTLS12})
	if err != nil {
		t.Fatalf("SNI api-gateway must verify against the internal CA: %v", err)
	}
	_ = conn.Close()

	conn, err = tls.Dial("tcp", addr, &tls.Config{InsecureSkipVerify: true, ServerName: "localhost", MinVersion: tls.VersionTLS12}) // #nosec G402 -- inspecting the served cert only
	if err != nil {
		t.Fatalf("dial localhost: %v", err)
	}
	served := conn.ConnectionState().PeerCertificates[0]
	_ = conn.Close()
	if served.Subject.CommonName != "external" {
		t.Fatalf("SNI localhost: expected external cert, got CN=%s", served.Subject.CommonName)
	}

	// No internal pair: everyone gets the external certificate.
	cfg, err = Config(extCert, extKey, "", "", "")
	if err != nil {
		t.Fatalf("Config without internal pair: %v", err)
	}
	got, _ := cfg.GetCertificate(&tls.ClientHelloInfo{ServerName: "api-gateway"})
	leaf, _ := x509.ParseCertificate(got.Certificate[0])
	if leaf.Subject.CommonName != "external" {
		t.Fatalf("without internal pair: expected external cert, got CN=%s", leaf.Subject.CommonName)
	}
}

// TestRequireInternalClientCert_OnlyVerifiedInternalClients pins that the
// gateway's /admin/* handlers answer only callers that presented a client
// certificate from the internal CA (console, auth-service). A client with no
// certificate, like the edge Caddy hop or an internet client, gets 403, and
// so does one holding a certificate from another CA.
func TestRequireInternalClientCert_OnlyVerifiedInternalClients(t *testing.T) {
	dir := t.TempDir()
	caPath, _, caCert, caKey := writeCert(t, dir, "ca", nil, true, nil, nil)
	intCert, intKey, _, _ := writeCert(t, dir, "api-gateway", []string{"api-gateway"}, false, caCert, caKey)
	extCert, extKey, _, _ := writeCert(t, dir, "external", []string{"localhost"}, false, nil, nil)
	clientCert, clientKey, _, _ := writeCert(t, dir, "reviewer-console", []string{"reviewer-console"}, false, caCert, caKey)
	rogueCert, rogueKey, _, _ := writeCert(t, dir, "rogue", []string{"rogue"}, false, nil, nil)

	cfg, err := Config(extCert, extKey, intCert, intKey, caPath)
	if err != nil {
		t.Fatalf("Config: %v", err)
	}
	srv := httptest.NewUnstartedServer(RequireInternalClientCert(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})))
	srv.TLS = cfg
	srv.StartTLS()
	defer srv.Close()

	pool := x509.NewCertPool()
	pool.AddCert(caCert)
	get := func(certFile, keyFile string) (int, error) {
		tc := &tls.Config{RootCAs: pool, ServerName: "api-gateway", MinVersion: tls.VersionTLS12}
		if certFile != "" {
			pair, err := tls.LoadX509KeyPair(certFile, keyFile)
			if err != nil {
				t.Fatal(err)
			}
			tc.Certificates = []tls.Certificate{pair}
		}
		client := &http.Client{Transport: &http.Transport{TLSClientConfig: tc}}
		resp, err := client.Get("https://" + srv.Listener.Addr().String() + "/admin/version")
		if err != nil {
			return 0, err
		}
		resp.Body.Close()
		return resp.StatusCode, nil
	}
	if code, err := get("", ""); err != nil || code != http.StatusForbidden {
		t.Fatalf("no client cert: expected 403, got %d (%v)", code, err)
	}
	if code, err := get(clientCert, clientKey); err != nil || code != http.StatusOK {
		t.Fatalf("internal client cert: expected 200, got %d (%v)", code, err)
	}
	// Go's client withholds a certificate the server's CA list does not
	// accept, so this is a 403 rather than a handshake error; never a 200.
	if code, err := get(rogueCert, rogueKey); err == nil && code != http.StatusForbidden {
		t.Fatalf("client cert from another CA: expected denial, got %d", code)
	}
}
