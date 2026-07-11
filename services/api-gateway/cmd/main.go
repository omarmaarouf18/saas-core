// API Gateway — Reverse proxy entry point.
//
// Routes incoming traffic to backend microservices based on path prefix.
// All target URLs are read from environment variables at startup.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/project/gateway/internal/config"
	"github.com/project/gateway/internal/middleware"
	"github.com/project/gateway/internal/proxy"
	"github.com/project/gateway/internal/ratelimit"
	"github.com/project/gateway/internal/resilience"
	"github.com/project/gateway/internal/tlsutil"
)

func main() {
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
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
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
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		info := map[string]any{
			"service": "api-gateway",
			"version": "0.1.0",
			"routes":  make([]map[string]string, 0, len(cfg.Routes)),
		}
		for _, route := range cfg.Routes {
			info["routes"] = append(info["routes"].([]map[string]string), map[string]string{
				"prefix": route.Prefix,
				"target": route.Target,
			})
		}
		json.NewEncoder(w).Encode(info)
	})

	// ---- Register reverse proxy routes ----
	for _, route := range cfg.Routes {
		resilientTransport := resilience.NewRoundTripper(clientTransport, route.Prefix, 2, 5*time.Second)
		handler, err := proxy.New(route, cfg.GatewaySecret, resilientTransport)
		if err != nil {
			log.Fatalf("Failed to create proxy for %s: %v", route.Prefix, err)
		}
		mux.Handle(route.Prefix, handler)
		log.Printf("Route registered: %s → %s (env: %s)", route.Prefix, route.Target, route.EnvKey)
	}


	// ---- Wrap with global rate limiting and logging middleware ----
	rl := ratelimit.NewRateLimiter(redisClient, 100, 1*time.Minute, "gateway")
	limiter := middleware.NewRateLimiter(rl)
	rateLimited := middleware.RateLimit(limiter)(mux)
	logged := middleware.Logging(cfg.AllowedOrigin)(rateLimited)

	// ---- Start server ----
	addr := ":" + cfg.Port
	log.Printf("API Gateway listening on %s", addr)
	log.Printf("Routes active: %d", len(cfg.Routes))
	if err := http.ListenAndServe(addr, logged); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}

