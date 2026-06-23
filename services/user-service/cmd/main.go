// User Service — Service discovery, job lifecycle, and financial operations.
//
// Endpoints:
//   GET  /users/services           — List & filter services (spatial index)
//   POST /users/services           — Create a service
//   POST /users/jobs/track         — Create job with escrow lock
//   POST /users/jobs/complete      — Complete job with profit split
//   GET  /users/wallet             — Get tenant wallet
//   POST /users/wallet/deposit     — Deposit funds
//   GET  /users/ledger             — Transaction ledger
//   GET  /users/platform/config    — Platform fee config
//   GET  /health                   — Health check
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

	"github.com/project/user-service/internal/handlers"
	"github.com/project/user-service/internal/store"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "3003"
	}
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017/saas_platform"
	}
	dbName := os.Getenv("MONGO_INITDB_DATABASE")
	if dbName == "" {
		dbName = "saas_platform"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		log.Fatalf("[USER] Failed to initialize MongoDB store: %v", err)
	}

	userHandlers := handlers.NewUserService(mongoStore)
	mux := http.NewServeMux()
	userHandlers.RegisterRoutes(mux)

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "storage": "mongodb"})
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{
			"service": "user-service", "version": "0.2.0", "storage": "mongodb",
		})
	})

	addr := ":" + port
	server := &http.Server{Addr: addr, Handler: mux}

	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		log.Println("[USER] Shutting down...")
		shutdownCtx, sc := context.WithTimeout(context.Background(), 10*time.Second)
		defer sc()
		server.Shutdown(shutdownCtx)
		mongoStore.Close(shutdownCtx)
	}()

	log.Printf("User Service listening on %s (MongoDB-backed)", addr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}
