// Chat Service — Real-time messaging via WebSocket.
//
// Endpoints (relative to this service):
//
//	GET  /chat/ws?token=<id>  — Upgrade to WebSocket, join hub
//	GET  /health              — Health check
//
// Via the API Gateway:
//
//	GET  /api/v1/chat/ws?token=<id>
//
// WebSocket message protocol (JSON):
//
//	→ { "action": "subscribe",   "channel": "general" }
//	→ { "action": "unsubscribe", "channel": "general" }
//	→ { "action": "message",     "channel": "general", "content": "hello" }
//	← { "type": "message", "channel": "general", "sender_id": "...", "content": "hello" }
package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/project/chat-service/internal/chat"
	"github.com/project/chat-service/internal/config"
	"github.com/project/chat-service/internal/handlers"
	"github.com/project/chat-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("[CHAT] Failed to load configuration: %v", err)
	}

	// Initialize JWT utility package.
	jwtutil.Init(cfg.JWTSecret)

	// Initialize TLS configuration to fail fast if missing/unreadable.
	tlsConfig, err := tlsutil.LoadServerTLSConfig(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
	if err != nil {
		log.Fatalf("[CHAT] Failed to load TLS configuration: %v", err)
	}

	// Connect to MongoDB.
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, cfg.MongoURI, cfg.MongoDatabase)
	if err != nil {
		log.Fatalf("[CHAT] Failed to initialize MongoDB store: %v", err)
	}

	// Create and start the WebSocket hub.
	hub := chat.NewHub()
	go hub.Run()

	// Connect to Redis.
	redisClient, err := ratelimit.NewRedisClient(cfg.RedisURI)
	if err != nil {
		log.Fatalf("[CHAT] Failed to connect to Redis: %v", err)
	}
	jwtutil.SetRedisClient(redisClient)

	// Create handler group and register routes.
	chatHandlers := handlers.NewChat(hub, mongoStore, cfg, redisClient)

	mux := http.NewServeMux()

	// WebSocket endpoint.
	chatHandlers.RegisterRoutes(mux)

	// Health check with connection stats.
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		handlerutil.WriteJSON(w, http.StatusOK, map[string]any{
			"status":          "ok",
			"active_clients":  hub.ClientCount(),
			"active_channels": hub.ChannelCount(),
			"dependencies":    resilience.GetBreakerStats(),
		})
	})

	// Service info (root).
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		handlerutil.WriteJSON(w, http.StatusOK, map[string]string{
			"service": "chat-service",
			"version": "0.1.0",
		})
	})

	addr := ":" + cfg.Port
	server := &http.Server{
		Addr:      addr,
		Handler:   mux,
		TLSConfig: tlsConfig,
	}

	log.Printf("Chat Service listening on %s (HTTPS)", addr)
	log.Printf("WebSocket endpoint: GET /chat/ws?token=<user_token>")
	if err := server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}
