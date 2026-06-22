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
)

// New creates an http.Handler that reverse-proxies requests matching
// the given ServiceRoute to its target backend.
//
// Path rewriting: only the API version prefix (StripPrefix) is removed,
// preserving each service's domain namespace:
//
//   - Gateway receives:  /api/v1/auth/signup
//   - Backend receives:  /auth/signup
//
// This lets each backend service own its own URL namespace cleanly.
func New(route config.ServiceRoute) (http.Handler, error) {
	target, err := url.Parse(route.Target)
	if err != nil {
		return nil, fmt.Errorf("proxy: invalid target URL %q for %s: %w",
			route.Target, route.Prefix, err)
	}

	proxy := &httputil.ReverseProxy{
		Director: func(req *http.Request) {
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
			if req.Header.Get("X-Forwarded-For") == "" {
				req.Header.Set("X-Forwarded-For", req.RemoteAddr)
			}
		},
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
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
