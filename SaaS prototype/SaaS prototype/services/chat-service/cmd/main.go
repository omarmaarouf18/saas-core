// Chat Service — Real-time messaging via WebSocket.
//
// Endpoints (relative to this service):
//   GET  /chat/ws?token=<id>  — Upgrade to WebSocket, join hub
//   GET  /health              — Health check
//
// Via the API Gateway:
//   GET  /api/v1/chat/ws?token=<id>
//
// WebSocket message protocol (JSON):
//   → { "action": "subscribe",   "channel": "general" }
//   → { "action": "unsubscribe", "channel": "general" }
//   → { "action": "message",     "channel": "general", "content": "hello" }
//   ← { "type": "message", "channel": "general", "sender_id": "...", "content": "hello" }
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/project/chat-service/internal/chat"
	"github.com/project/chat-service/internal/handlers"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "3001"
	}

	// Create and start the WebSocket hub.
	hub := chat.NewHub()
	go hub.Run()

	// Create handler group and register routes.
	chatHandlers := handlers.NewChat(hub)

	mux := http.NewServeMux()

	// WebSocket endpoint.
	chatHandlers.RegisterRoutes(mux)

	// Health check with connection stats.
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"status":           "ok",
			"active_clients":   hub.ClientCount(),
			"active_channels":  hub.ChannelCount(),
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
			"service": "chat-service",
			"version": "0.1.0",
		})
	})

	addr := ":" + port
	log.Printf("Chat Service listening on %s", addr)
	log.Printf("WebSocket endpoint: GET /chat/ws?token=<user_token>")
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
