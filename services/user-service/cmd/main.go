// User Service — Service discovery, job lifecycle, and financial operations.
//
// Endpoints:
//
//	GET  /users/services           — List & filter services (spatial index)
//	POST /users/services           — Create a service
//	POST /users/jobs/track         — Create job with escrow lock
//	POST /users/jobs/complete      — Complete job with profit split
//	GET  /users/wallet             — Get tenant wallet
//	POST /users/wallet/deposit     — Deposit funds
//	GET  /users/ledger             — Transaction ledger
//	GET  /users/platform/config    — Platform fee config
//	GET  /health                   — Health check
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/handlers"
	"github.com/project/user-service/internal/store"
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
		fmt.Println("PREFLIGHT OK: user-service config validated")
		os.Exit(0)
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("[USER] Failed to load configuration: %v", err)
	}

	// Initialize JWT utility package.
	jwtutil.Init(cfg.JWTSecret)

	// Initialize TLS configuration to fail fast if missing/unreadable.
	tlsConfig, err := tlsutil.LoadServerTLSConfig(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
	if err != nil {
		log.Fatalf("[USER] Failed to load TLS configuration: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, cfg.MongoURI, cfg.MongoDatabase)
	if err != nil {
		log.Fatalf("[USER] Failed to initialize MongoDB store: %v", err)
	}

	// Connect to Redis.
	redisClient, err := ratelimit.NewRedisClient(cfg.RedisURI)
	if err != nil {
		log.Fatalf("[USER] Failed to connect to Redis: %v", err)
	}
	jwtutil.SetRedisClient(redisClient)

	userHandlers := handlers.NewUserService(mongoStore, cfg, redisClient)
	mux := http.NewServeMux()
	userHandlers.RegisterRoutes(mux)

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		handlerutil.WriteJSON(w, http.StatusOK, map[string]any{
			"status":       "ok",
			"storage":      "mongodb",
			"dependencies": resilience.GetBreakerStats(),
		})
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		handlerutil.WriteJSON(w, http.StatusOK, map[string]string{
			"service": "user-service", "version": "0.2.0", "storage": "mongodb",
		})
	})

	addr := ":" + cfg.Port
	server := &http.Server{
		Addr:              addr,
		Handler:           mux,
		TLSConfig:         tlsConfig,
		ReadHeaderTimeout: 3 * time.Second,
	}

	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		log.Println("[USER] Shutting down...")
		shutdownCtx, sc := context.WithTimeout(context.Background(), 10*time.Second)
		defer sc()
		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("[ERROR] server shutdown error: %v", err)
		}
		if err := mongoStore.Close(shutdownCtx); err != nil {
			log.Printf("[ERROR] mongo store close error: %v", err)
		}
	}()

	log.Printf("User Service listening on %s (HTTPS, MongoDB-backed)", addr)
	if err := server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}
