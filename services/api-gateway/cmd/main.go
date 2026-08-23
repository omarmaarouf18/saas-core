// API Gateway — Reverse proxy entry point.
//
// Routes incoming traffic to backend microservices based on path prefix.
// All target URLs are read from environment variables at startup.
package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/project/gateway/internal/config"
	"github.com/project/gateway/internal/middleware"
	"github.com/project/gateway/internal/proxy"
	"github.com/project/gateway/internal/version"
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

	// ---- Initialize App Version Store ----
	versionStore := version.NewStore(nil, "")

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
		// Empty-secret guard (QA audit Q23): never authenticate when unconfigured.
		if cfg.InternalServiceToken == "" || subtle.ConstantTimeCompare([]byte(gotToken), []byte(cfg.InternalServiceToken)) != 1 {
			handlerutil.WriteJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: invalid internal token"})
			return
		}
		handlerutil.WriteJSON(w, http.StatusOK, map[string]any{
			"status":       "ok",
			"dependencies": resilience.GetBreakerStats(),
		})
	})

	// ---- Admin App Version Configuration Endpoint ----
	mux.HandleFunc("/api/v1/admin/version-config", func(w http.ResponseWriter, r *http.Request) {
		gotToken := r.Header.Get("X-Internal-Token")
		// Empty-secret guard (QA audit Q23): never authenticate when unconfigured.
		if cfg.InternalServiceToken == "" || subtle.ConstantTimeCompare([]byte(gotToken), []byte(cfg.InternalServiceToken)) != 1 {
			handlerutil.WriteJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: invalid internal token"})
			return
		}

		if r.Method == http.MethodGet {
			vConfig, err := versionStore.GetConfig(r.Context())
			if err != nil {
				handlerutil.WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			handlerutil.WriteJSON(w, http.StatusOK, vConfig)
			return
		}

		if r.Method == http.MethodPut {
			var req version.PlatformVersions
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
				return
			}
			updated, err := versionStore.UpdateConfig(r.Context(), req)
			if err != nil {
				handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			handlerutil.WriteJSON(w, http.StatusOK, map[string]any{"message": "version configuration updated successfully", "config": updated})
			return
		}

		handlerutil.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
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

	// ---- Wrap with version gate, rate limiting, and logging middleware ----
	rl := ratelimit.NewRateLimiter(redisClient, 100, 1*time.Minute, "gateway")
	limiter := middleware.NewRateLimiter(rl, cfg.TrustedProxyIPs)
	versionGated := middleware.VersionGate(versionStore)(mux)
	rateLimited := middleware.RateLimit(limiter)(versionGated)
	logged := middleware.Logging(cfg.AllowedOrigin)(rateLimited)

	// ---- Start server ----
	addr := ":" + cfg.Port
	log.Printf("API Gateway listening on HTTPS %s", addr)
	log.Printf("Routes active: %d", len(cfg.Routes))
	server := &http.Server{
		Addr:    addr,
		Handler: logged,
		// ReadTimeout bounds slow-body slowloris reads (request headers
		// were already capped at 3s). IdleTimeout reaps idle keep-alive
		// connections. WriteTimeout is deliberately unset: SSE streams and
		// proxied long-lived responses must never be truncated by a write
		// deadline.
		ReadHeaderTimeout: 3 * time.Second,
		ReadTimeout:       30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	// Graceful shutdown.
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		log.Println("[GATEWAY] Shutting down...")

		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer shutdownCancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("[ERROR] server shutdown error: %v", err)
		}
	}()

	if err := server.ListenAndServeTLS(cfg.ExternalTLSCertPath, cfg.ExternalTLSKeyPath); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}
