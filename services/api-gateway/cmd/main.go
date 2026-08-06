// API Gateway — Reverse proxy entry point.
//
// Routes incoming traffic to backend microservices based on path prefix.
// All target URLs are read from environment variables at startup.
package main

import (
	"crypto/subtle"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/project/gateway/internal/config"
	"github.com/project/gateway/internal/middleware"
	"github.com/project/gateway/internal/proxy"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
)

func main() {
	// --check-env: validate config and exit without starting the server.
	// Used by the CD pipeline pre-flight to verify env vars before deployment.
	if len(os.Args) > 1 && os.Args[1] == "--check-env" {
		_, err := config.Load()
		if err != nil {
			fmt.Fprintf(os.Stderr, "PREFLIGHT FAILED: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("PREFLIGHT OK: api-gateway config validated")
		os.Exit(0)
	}

	// ---- Load configuration from environment ----
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// ---- Initialize Redis rate limiter client ----
	redisClient, err := ratelimit.NewRedisClient(cfg.RedisURI)
	if err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}

	var clientTransport http.RoundTripper
	if cfg.TLSCertPath != "" && cfg.TLSKeyPath != "" && cfg.TLSCAPath != "" {
		tlsConfig, err := tlsutil.LoadClientTLSConfig(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
		if err != nil {
			log.Fatalf("Failed to load gateway client TLS config: %v", err)
		}
		clientTransport = &http.Transport{
			TLSClientConfig: tlsConfig,
		}
	} else {
		clientTransport = http.DefaultTransport
	}

	mux := http.NewServeMux()

	// ---- Health check endpoint ----
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		handlerutil.WriteJSON(w, http.StatusOK, map[string]any{
			"status": "ok",
		})
	})

	// ---- Internal Health check endpoint ----
	mux.HandleFunc("/health/internal", func(w http.ResponseWriter, r *http.Request) {
		gotToken := r.Header.Get("X-Internal-Token")
		if subtle.ConstantTimeCompare([]byte(gotToken), []byte(cfg.InternalServiceToken)) != 1 {
			handlerutil.WriteJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: invalid internal token"})
			return
		}
		handlerutil.WriteJSON(w, http.StatusOK, map[string]any{
			"status":       "ok",
			"dependencies": resilience.GetBreakerStats(),
		})
	})

	// ---- Service info endpoint ----
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Only match the exact root path; anything else should 404.
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		info := map[string]any{
			"service": "api-gateway",
			"version": "0.1.0",
		}
		handlerutil.WriteJSON(w, http.StatusOK, info)
	})

	// ---- Register reverse proxy routes ----
	for _, route := range cfg.Routes {
		resilientTransport := resilience.NewRoundTripper(clientTransport, route.Prefix, 2, 5*time.Second)
		handler, err := proxy.New(route, cfg.GatewaySecret, cfg.TrustedProxyIPs, resilientTransport)
		if err != nil {
			log.Fatalf("Failed to create proxy for %s: %v", route.Prefix, err)
		}
		mux.Handle(route.Prefix, handler)
		log.Printf("Route registered: %s → %s (env: %s)", route.Prefix, route.Target, route.EnvKey)
	}

	// ---- Wrap with global rate limiting and logging middleware ----
	rl := ratelimit.NewRateLimiter(redisClient, 100, 1*time.Minute, "gateway")
	limiter := middleware.NewRateLimiter(rl, cfg.TrustedProxyIPs)
	rateLimited := middleware.RateLimit(limiter)(mux)
	logged := middleware.Logging(cfg.AllowedOrigin)(rateLimited)

	// ---- Start server ----
	addr := ":" + cfg.Port
	log.Printf("API Gateway listening on HTTPS %s", addr)
	log.Printf("Routes active: %d", len(cfg.Routes))
	server := &http.Server{
		Addr:              addr,
		Handler:           logged,
		ReadHeaderTimeout: 3 * time.Second,
	}
	if err := server.ListenAndServeTLS(cfg.ExternalTLSCertPath, cfg.ExternalTLSKeyPath); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}
