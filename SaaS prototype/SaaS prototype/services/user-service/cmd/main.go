// User Service — Service discovery and job lifecycle tracking.
//
// Endpoints (relative to this service):
//   GET  /users/services?sort_by=price&near_by=true  — List & filter services
//   POST /users/jobs/track                            — Create a job tracking record
//   GET  /health                                      — Health check
//
// Via the API Gateway:
//   GET  /api/v1/users/services?sort_by=price&near_by=true
//   POST /api/v1/users/jobs/track
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/project/user-service/internal/handlers"
	"github.com/project/user-service/internal/store"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "3003"
	}

	// Initialize in-memory store (pre-seeded with sample services).
	memStore := store.NewMemory()

	// Create handler group and register routes.
	userHandlers := handlers.NewUserService(memStore)

	mux := http.NewServeMux()

	// User-service endpoints.
	userHandlers.RegisterRoutes(mux)

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
			"service": "user-service",
			"version": "0.1.0",
		})
	})

	addr := ":" + port
	log.Printf("User Service listening on %s", addr)
	log.Printf("Endpoints: GET /users/services, POST /users/services, POST /users/jobs/track")
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
