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
	"encoding/json"
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
		cfg, err := config.Load()
		if err != nil {
			fmt.Fprintf(os.Stderr, "PREFLIGHT FAILED: %v\n", err)
			os.Exit(1)
		}
		for _, w := range cfg.Warnings {
			fmt.Fprintf(os.Stderr, "PREFLIGHT WARNING: %s\n", w)
		}
		fmt.Println("PREFLIGHT OK: user-service config validated")
		os.Exit(0)
	}

	// --count-unfunded-digital-jobs: read-only PAY-COD-ONLY check. Prints
	// how many non-COD jobs never had escrow locked, by status, as JSON.
	if len(os.Args) > 1 && os.Args[1] == "--count-unfunded-digital-jobs" {
		os.Exit(runCountUnfundedDigitalJobs())
	}

	// --count-stuck-cod-reconciliation-jobs: read-only FIX-COD-RECON check.
	// Prints how many COD jobs sit in escrow_reconciliation_required with no
	// locked escrow, by escrow_failure_reason, as JSON.
	if len(os.Args) > 1 && os.Args[1] == "--count-stuck-cod-reconciliation-jobs" {
		os.Exit(runCountStuckCODReconciliationJobs())
	}

	// --repair-stuck-cod-reconciliation-jobs [--confirm]: FIX-COD-RECON
	// repair. Without --confirm it is a dry run that prints the plan; with
	// --confirm it completes the under-distance COD jobs (cash = booked
	// amount, distance_review flag set). Idempotent.
	if len(os.Args) > 1 && os.Args[1] == "--repair-stuck-cod-reconciliation-jobs" {
		os.Exit(runRepairStuckCODReconciliationJobs(os.Args[2:]))
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
		Addr:      addr,
		Handler:   handlerutil.MaxBytesMiddleware(1 << 20)(mux),
		TLSConfig: tlsConfig,
		// ReadTimeout bounds slow-body slowloris reads (request headers
		// were already capped at 3s). IdleTimeout reaps idle keep-alive
		// connections. WriteTimeout is deliberately unset: SSE streams and
		// proxied long-lived responses must never be truncated by a write
		// deadline.
		ReadHeaderTimeout: 3 * time.Second,
		ReadTimeout:       30 * time.Second,
		IdleTimeout:       120 * time.Second,
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

// runCountUnfundedDigitalJobs implements --count-unfunded-digital-jobs.
func runCountUnfundedDigitalJobs() int {
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "config: %v\n", err)
		return 1
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	report, err := store.CountUnfundedDigitalJobsAt(ctx, cfg.MongoURI, cfg.MongoDatabase)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	out, _ := json.Marshal(report)
	fmt.Println(string(out))
	return 0
}

// runCountStuckCODReconciliationJobs implements --count-stuck-cod-reconciliation-jobs.
func runCountStuckCODReconciliationJobs() int {
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "config: %v\n", err)
		return 1
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	report, err := store.CountStuckCODReconciliationJobsAt(ctx, cfg.MongoURI, cfg.MongoDatabase)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	out, _ := json.Marshal(report)
	fmt.Println(string(out))
	return 0
}

// runRepairStuckCODReconciliationJobs implements
// --repair-stuck-cod-reconciliation-jobs [--confirm]. Writes happen only
// with exactly --confirm; any other argument is refused.
func runRepairStuckCODReconciliationJobs(args []string) int {
	apply := false
	for _, a := range args {
		if a != "--confirm" {
			fmt.Fprintf(os.Stderr, "unknown argument %q (only --confirm is accepted)\n", a)
			return 2
		}
		apply = true
	}
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "config: %v\n", err)
		return 1
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	result, err := store.RepairStuckCODReconciliationJobsAt(ctx, cfg.MongoURI, cfg.MongoDatabase, apply)
	if result != nil {
		out, _ := json.Marshal(result)
		fmt.Println(string(out))
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	if !apply {
		fmt.Fprintln(os.Stderr, "dry run: nothing written; pass --confirm to apply")
	}
	return 0
}
