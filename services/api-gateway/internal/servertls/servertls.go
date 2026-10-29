// Package servertls builds the gateway listener's TLS config. It lives
// outside cmd/ because the Dockerfile compiles ./cmd/main.go alone.
package servertls

import (
	"crypto/tls"
	"fmt"
	"strings"
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
func Config(externalCert, externalKey, internalCert, internalKey string) (*tls.Config, error) {
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
	return &tls.Config{
		MinVersion: tls.VersionTLS12,
		GetCertificate: func(hello *tls.ClientHelloInfo) (*tls.Certificate, error) {
			if internal != nil && strings.EqualFold(hello.ServerName, internalServerName) {
				return internal, nil
			}
			return &external, nil
		},
	}, nil
}
