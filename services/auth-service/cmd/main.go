// Auth Service — Multi-role authentication with signup, login, and 2FA.
//
// Endpoints (relative to this service):
//
//	POST /auth/signup             — Register with role-based handling + OTP
//	POST /auth/login              — Validate credentials, trigger 2FA OTP
//	POST /auth/verify-otp         — Complete 2FA flow (AES-256 decrypted)
//	POST /auth/employee/toggle    — Freeze/activate employee accounts
//	POST /auth/employee/action    — Simulate employee action (audit log)
//	GET  /auth/audit-log          — Retrieve audit log
//	GET  /health                  — Health check
//
// OTP Flow:
//  1. Generate 6-digit OTP
//  2. Encrypt via AES-256-GCM → store ciphertext in MongoDB
//  3. Dispatch via OTPDispatcher (MockSMS/MockEmail in local mode)
//  4. When APP_ENV=local, plaintext OTP is exposed as "dev_otp" in response
//  5. /auth/verify-otp decrypts stored ciphertext and compares
//
// Environment Variables:
//
//	APP_ENV          — "local" enables dev_otp exposure + mock dispatchers
//	OTP_AES_KEY      — 32-byte hex key for AES-256-GCM (auto-generated if empty)
//	MONGO_URI        — MongoDB connection string
//	MONGO_INITDB_DATABASE — Database name
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

	"github.com/project/auth-service/internal/config"
	"github.com/project/auth-service/internal/handlers"
	"github.com/project/auth-service/internal/otp"
	"github.com/project/auth-service/internal/otpcrypto"
	"github.com/project/auth-service/internal/storage"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
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
		fmt.Println("PREFLIGHT OK: auth-service config validated")
		os.Exit(0)
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("[AUTH] Failed to load configuration: %v", err)
	}

	// Initialize JWT utility package.
	jwtutil.Init(cfg.JWTSecret)

	// Initialize TLS configuration to fail fast if missing/unreadable.
	tlsConfig, err := tlsutil.LoadServerTLSConfig(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
	if err != nil {
		log.Fatalf("[AUTH] Failed to load TLS configuration: %v", err)
	}

	// Initialize AES-256-GCM cipher for OTP encryption at rest.
	otpCipher, err := otpcrypto.NewCipher(cfg.OTPAESKey, cfg.AppEnv)
	if err != nil {
		log.Fatalf("[AUTH] Failed to initialize OTP cipher: %v", err)
	}
	if cfg.OTPAESKey == "" {
		log.Println("[AUTH] ⚠ OTP_AES_KEY not set — using ephemeral key (OTPs will not survive restarts)")
	}

	// Connect to MongoDB with OTP cipher.
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, cfg.MongoURI, cfg.MongoDatabase, otpCipher)
	if err != nil {
		log.Fatalf("[AUTH] Failed to initialize MongoDB store: %v", err)
	}
	mongoStore.StartOTPCleanup(context.Background(), 1*time.Minute)

	// Select OTP dispatcher based on environment. Production environments
	// must have a real dispatcher configured — silently falling back to the
	// stdout-printing mock would leak every OTP code into container logs.
	dispatcher, err := selectOTPDispatcher(cfg.AppEnv, cfg.ResendAPIKey, cfg.ResendFromEmail)
	if err != nil {
		log.Fatalf("[AUTH] %v", err)
	}
	log.Printf("[AUTH] OTP dispatcher: %s", dispatcher.Name())

	// Connect to Redis for rate limiting.
	redisClient, err := ratelimit.NewRedisClient(cfg.RedisURI)
	if err != nil {
		log.Fatalf("[AUTH] Failed to connect to Redis: %v", err)
	}
	jwtutil.SetRedisClient(redisClient)

	// Initialize local document storage for KYB/KYE with dedicated signing secret & AES-256-GCM encryption key
	docStorage, err := storage.NewLocalStorage(cfg.StorageBaseDir, cfg.StorageBaseURL, cfg.DocumentSigningSecret, cfg.DocumentEncryptionKey, cfg.AppEnv)
	if err != nil {
		log.Fatalf("[AUTH] Failed to initialize storage: %v", err)
	}

	// Create handler group and register routes.
	authHandlers := handlers.NewAuth(mongoStore, dispatcher, cfg, redisClient, docStorage)

	mux := http.NewServeMux()

	// Auth endpoints.
	authHandlers.RegisterRoutes(mux)

	// Health check.
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		handlerutil.WriteJSON(w, http.StatusOK, map[string]string{
			"status":       "ok",
			"storage":      "mongodb",
			"otp_crypto":   "AES-256-GCM",
			"otp_dispatch": dispatcher.Name(),
			"app_env":      cfg.AppEnv,
		})
	})

	// Service info (root).
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		handlerutil.WriteJSON(w, http.StatusOK, map[string]string{
			"service": "auth-service",
			"version": "0.3.0",
			"storage": "mongodb",
		})
	})

	addr := ":" + cfg.Port
	server := &http.Server{
		Addr:      addr,
		Handler:   mux,
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

	// Graceful shutdown.
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		log.Println("[AUTH] Shutting down...")

		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer shutdownCancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("[ERROR] server shutdown error: %v", err)
		}
		if err := mongoStore.Close(shutdownCtx); err != nil {
			log.Printf("[ERROR] mongo store close error: %v", err)
		}
	}()

	log.Printf("Auth Service listening on %s (HTTPS + MongoDB + AES-256-GCM + %s)", addr, dispatcher.Name())
	log.Printf("Endpoints: POST /auth/signup, POST /auth/login, POST /auth/verify-otp, POST /auth/resend-otp")
	if err := server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}

}

// selectOTPDispatcher chooses the OTP delivery mechanism for the current
// environment. Local/dev environments use the stdout mock; every other
// environment REQUIRES a configured Resend dispatcher and refuses to start
// otherwise — an insecure silent fallback would print OTP codes to logs.
func selectOTPDispatcher(appEnv, resendAPIKey, resendFromEmail string) (otp.OTPDispatcher, error) {
	switch appEnv {
	case "local", "dev", "development":
		return &otp.MockSMSDispatcher{}, nil
	default:
		if resendAPIKey == "" {
			return nil, fmt.Errorf("no production OTP dispatcher configured: RESEND_API_KEY is required when APP_ENV=%q (refusing to fall back to the stdout-printing mock)", appEnv)
		}
		return otp.NewResendDispatcher(resendAPIKey, resendFromEmail), nil
	}
}
