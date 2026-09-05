// Package proxy provides reverse proxy handler creation for backend services.
package proxy

import (
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"

	"github.com/project/gateway/internal/config"
	"github.com/project/gateway/internal/iputil"
)

// New creates an http.Handler that reverse-proxies requests matching
// the given ServiceRoute to its target backend.
func New(route config.ServiceRoute, gatewaySecret string, trustedProxies []string, transport http.RoundTripper) (http.Handler, error) {
	target, err := url.Parse(route.Target)
	if err != nil {
		return nil, fmt.Errorf("proxy: invalid target URL %q for %s: %w",
			route.Target, route.Prefix, err)
	}

	proxy := &httputil.ReverseProxy{
		Transport:     transport,
		FlushInterval: -1,
		Director: func(req *http.Request) {
			req.Header.Del("X-Internal-Token")
			req.URL.Scheme = target.Scheme
			req.URL.Host = target.Host
			req.Host = target.Host

			// Strip only the API version prefix, keeping the service namespace.
			originalPath := req.URL.Path
			trimmed := strings.TrimPrefix(originalPath, route.StripPrefix)
			if trimmed == "" || trimmed[0] != '/' {
				trimmed = "/" + trimmed
			}
			req.URL.Path = trimmed

			// Preserve the original path in a header for backend observability.
			req.Header.Set("X-Forwarded-Prefix", route.Prefix)

			// Trust Chain Hop 1 (Caddy -> api-gateway):
			// api-gateway only trusts X-Forwarded-For if the immediate connection (req.RemoteAddr)
			// comes from a trusted proxy IP/CIDR in TRUSTED_PROXY_IPS (default 127.0.0.1, ::1).
			// If untrusted (direct client bypass/spoof), api-gateway overwrites X-Forwarded-For
			// with req.RemoteAddr to prevent client IP spoofing attacks.
			immediateIP := iputil.ExtractIP(req.RemoteAddr)
			existingXFF := req.Header.Get("X-Forwarded-For")

			if iputil.IsTrustedProxy(immediateIP, trustedProxies) && existingXFF != "" {
				// Trusted proxy with existing XFF chain: preserve existing XFF chain.
				// Note: httputil.ReverseProxy automatically appends immediateIP onto X-Forwarded-For.
				req.Header.Set("X-Forwarded-For", existingXFF)
			} else {
				// Untrusted connection or missing XFF: overwrite with RemoteAddr (hardened behavior)
				req.Header.Set("X-Forwarded-For", req.RemoteAddr)
			}

			req.Header.Set("X-Gateway-Secret", gatewaySecret)
		},
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			// #nosec G706 //nolint:gosec -- log statement contains sanitised request path and method, log injection not possible
			log.Printf("[PROXY ERROR] %s %s → %s: %v",
				r.Method, r.URL.Path, route.Target, err)
			http.Error(w,
				fmt.Sprintf(`{"error": "service unavailable", "target": %q}`, route.Prefix),
				http.StatusBadGateway,
			)
		},
	}

	return proxy, nil
}
