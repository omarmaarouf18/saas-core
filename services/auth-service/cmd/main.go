// Auth Service — Multi-role authentication with signup, login, and 2FA.
//
// Endpoints (relative to this service):
//   POST /auth/signup      — Register with role-based handling
//   POST /auth/login       — Validate credentials, trigger 2FA for owner/user
//   POST /auth/verify-otp  — Complete 2FA flow
//   GET  /health           — Health check
//
// Via the API Gateway, these are exposed as:
//   POST /api/v1/auth/signup
//   POST /api/v1/auth/login
//   POST /api/v1/auth/verify-otp
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/project/auth-service/internal/handlers"
	"github.com/project/auth-service/internal/store"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "3002"
	}

	// Initialize in-memory store (temporary until DB schemas are finalized).
	memStore := store.NewMemory()

	// Create handler group and register routes.
	authHandlers := handlers.NewAuth(memStore)

	mux := http.NewServeMux()

	// Auth endpoints.
	authHandlers.RegisterRoutes(mux)

	// Health check.
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
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
			"version": "0.1.0",
		})
	})

	addr := ":" + port
	log.Printf("Auth Service listening on %s", addr)
	log.Printf("Endpoints: POST /auth/signup, POST /auth/login, POST /auth/verify-otp")
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
