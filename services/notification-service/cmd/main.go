// Notification Service — Real-time SSE notifications with role-based broadcasting.
//
// Endpoints:
//   GET  /notifications/stream              — SSE stream (token, tenant_id, role)
//   POST /notifications/send                — Push notification to connected clients
//   POST /notifications/broadcast/job-alert — Broadcast job alert to all roles
//   GET  /health                            — Health check with client stats
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/project/notification-service/internal/handlers"
	"github.com/project/notification-service/internal/hub"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "3004"
	}

	sseHub := hub.NewSSEHub()
	notifHandlers := handlers.NewNotification(sseHub)

	mux := http.NewServeMux()
	notifHandlers.RegisterRoutes(mux)

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"status":          "ok",
			"active_clients":  sseHub.ClientCount(),
			"clients_by_role": sseHub.ClientsByRole(),
		})
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{
			"service": "notification-service",
			"version": "0.2.0",
			"transport": "SSE",
		})
	})

	addr := ":" + port
	log.Printf("Notification Service listening on %s (SSE)", addr)
	log.Printf("Endpoints: GET /notifications/stream, POST /notifications/send, POST /notifications/broadcast/job-alert")
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
