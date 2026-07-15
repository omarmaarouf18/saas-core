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
//  1. Generate 4-digit OTP
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
	"encoding/json"
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
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/tlsutil"
)

func main() {
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

	// Select OTP dispatcher based on environment.
	var dispatcher otp.OTPDispatcher
	switch cfg.AppEnv {
	case "local", "dev", "development":
		dispatcher = &otp.MockSMSDispatcher{}
		log.Printf("[AUTH] OTP dispatcher: %s (no external network calls)", dispatcher.Name())
	default:
		// In production, this would be a real SMS/Email dispatcher.
		// For now, fall back to mock with a warning.
		dispatcher = &otp.MockSMSDispatcher{}
		log.Printf("[AUTH] ⚠ No production OTP dispatcher configured — using %s", dispatcher.Name())
	}

	// Connect to Redis for rate limiting.
	redisClient, err := ratelimit.NewRedisClient(cfg.RedisURI)
	if err != nil {
		log.Fatalf("[AUTH] Failed to connect to Redis: %v", err)
	}
	jwtutil.SetRedisClient(redisClient)

	// Initialize local document storage for KYB/KYE
	docStorage, err := storage.NewLocalStorage(cfg.StorageBaseDir, cfg.StorageBaseURL, cfg.JWTSecret)
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
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{
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
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{
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
	}

	// Graceful shutdown.
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		log.Println("[AUTH] Shutting down...")

		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer shutdownCancel()

		server.Shutdown(shutdownCtx)
		mongoStore.Close(shutdownCtx)
	}()

	log.Printf("Auth Service listening on %s (HTTPS + MongoDB + AES-256-GCM + %s)", addr, dispatcher.Name())
	log.Printf("Endpoints: POST /auth/signup, POST /auth/login, POST /auth/verify-otp")
	if err := server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}

}
