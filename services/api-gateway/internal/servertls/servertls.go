// Package servertls builds the gateway listener's TLS config. It lives
// outside cmd/ because the Dockerfile compiles ./cmd/main.go alone.
package servertls

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net/http"
	"os"
	"strings"

	"github.com/project/shared/infra/handlerutil"
)

// internalServerName is the SNI that saas-net callers (kyc-reviewer-console,
// auth-service) send when they dial https://api-gateway:<port>.
const internalServerName = "api-gateway"

// Config returns the gateway listener's TLS config. A client that
// asks for SNI "api-gateway" gets the internal certificate (signed by the
// internal mTLS CA, SAN api-gateway), so the console and auth-service can
// verify the gateway's internal reviewer endpoints (/admin/version,
// /admin/internal/audit). Every other client, including the edge Caddy hop,
// gets the external certificate as before. Without an internal pair the
// external certificate is served to everyone.
//
// With clientCAPath set, clients MAY present a certificate (never required,
// so the edge Caddy hop is unaffected); a presented one must chain to that
// CA. RequireInternalClientCert then gates the internal-only handlers.
func Config(externalCert, externalKey, internalCert, internalKey, clientCAPath string) (*tls.Config, error) {
	external, err := tls.LoadX509KeyPair(externalCert, externalKey)
	if err != nil {
		return nil, fmt.Errorf("load external TLS key pair: %w", err)
	}
	var internal *tls.Certificate
	if internalCert != "" && internalKey != "" {
		pair, err := tls.LoadX509KeyPair(internalCert, internalKey)
		if err != nil {
			return nil, fmt.Errorf("load internal TLS key pair: %w", err)
		}
		internal = &pair
	}
	var clientCAs *x509.CertPool
	clientAuth := tls.NoClientCert
	if clientCAPath != "" {
		pem, err := os.ReadFile(clientCAPath) // #nosec G304 -- path comes from trusted config (TLS_CA_PATH)
		if err != nil {
			return nil, fmt.Errorf("read client CA: %w", err)
		}
		clientCAs = x509.NewCertPool()
		if !clientCAs.AppendCertsFromPEM(pem) {
			return nil, fmt.Errorf("client CA %s holds no PEM certificate", clientCAPath)
		}
		clientAuth = tls.VerifyClientCertIfGiven
	}
	return &tls.Config{
		MinVersion: tls.VersionTLS12,
		ClientAuth: clientAuth,
		ClientCAs:  clientCAs,
		GetCertificate: func(hello *tls.ClientHelloInfo) (*tls.Certificate, error) {
			if internal != nil && strings.EqualFold(hello.ServerName, internalServerName) {
				return internal, nil
			}
			return &external, nil
		},
	}, nil
}

// RequireInternalClientCert lets a request through only when its TLS
// connection presented a client certificate that verified against the
// internal CA (see Config). The gateway's own reviewer endpoints (/admin/*)
// use it so they stay internal-only even if an edge rule is missing: the
// edge Caddy hop and internet clients present no such certificate.
func RequireInternalClientCert(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.TLS == nil || len(r.TLS.VerifiedChains) == 0 {
			handlerutil.WriteJSON(w, http.StatusForbidden, map[string]string{"error": "internal client certificate required"})
			return
		}
		next.ServeHTTP(w, r)
	})
}
