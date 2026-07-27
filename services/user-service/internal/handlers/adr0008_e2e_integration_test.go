package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/gorilla/websocket"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

type mockWSClient struct {
	conn     *websocket.Conn
	channels map[string]bool
	send     chan []byte
}

func TestADR0008_E2E_LiveEmployeeMapTracking(t *testing.T) {
	jwtSecret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", jwtSecret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_e2e_adr0008_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping E2E test: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	ownerID := "owner-e2e-adr0008"
	empID := "emp-e2e-adr0008"
	custID := "cust-e2e-adr0008"

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")

		if id == ownerID {
			json.NewEncoder(w).Encode(map[string]any{
				"id":         id,
				"role":       "owner",
				"kyc_status": "approved",
				"is_active":  true,
				"tenant_id":  ownerID,
			})
			return
		}
		if id == empID {
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "employee",
				"is_active": true,
				"tenant_id": ownerID,
			})
			return
		}
		json.NewEncoder(w).Encode(map[string]any{
			"id":        id,
			"role":      "user",
			"is_active": true,
			"tenant_id": id,
		})
	}))
	defer mockAuthServer.Close()

	var rdb *redis.Client
	mr, mrErr := miniredis.Run()
	if mrErr == nil {
		defer mr.Close()
		rdb = redis.NewClient(&redis.Options{Addr: mr.Addr()})
		defer rdb.Close()
	} else {
		redisURI := os.Getenv("REDIS_URI")
		var rdbOpts *redis.Options
		if redisURI != "" {
			if opts, err := redis.ParseURL(redisURI); err == nil {
				rdbOpts = opts
			}
		}
		if rdbOpts == nil {
			redisAddr := os.Getenv("REDIS_ADDR")
			if redisAddr == "" {
				redisAddr = "localhost:6379"
			}
			rdbOpts = &redis.Options{Addr: redisAddr}
		}
		rdb = redis.NewClient(rdbOpts)
		defer rdb.Close()

		pingCtx, pingCancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer pingCancel()
		if err := rdb.Ping(pingCtx).Err(); err != nil {
			t.Skipf("Skipping E2E test: Redis not reachable at %s (%v)", rdbOpts.Addr, err)
			return
		}
	}

	// 1. Setup real chat-service WebSocket and broadcast HTTP server
	var clientMu sync.Mutex
	clients := make([]*mockWSClient, 0)

	upgrader := websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}

	chatMux := http.NewServeMux()
	chatMux.HandleFunc("/chat/ws", func(w http.ResponseWriter, r *http.Request) {
		token := r.URL.Query().Get("token")
		claims, err := jwtutil.ValidateToken(token)
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}

		client := &mockWSClient{
			conn:     conn,
			channels: make(map[string]bool),
			send:     make(chan []byte, 256),
		}

		clientMu.Lock()
		clients = append(clients, client)
		clientMu.Unlock()

		go func() {
			for msg := range client.send {
				_ = conn.WriteMessage(websocket.TextMessage, msg)
			}
		}()

		for {
			var in map[string]string
			if err := conn.ReadJSON(&in); err != nil {
				break
			}
			if in["action"] == "subscribe" {
				ch := in["channel"]
				// Validate fleet channel authorization
				if strings.HasPrefix(ch, "fleet:") {
					fleetOwner := strings.TrimPrefix(ch, "fleet:")
					if claims.UserID != fleetOwner || claims.Role != "owner" {
						_ = conn.WriteJSON(map[string]string{"type": "error", "error": "not authorized"})
						continue
					}
				}
				clientMu.Lock()
				client.channels[ch] = true
				clientMu.Unlock()
				_ = conn.WriteJSON(map[string]string{"type": "subscribed", "channel": ch})
			}
		}
	})

	chatMux.HandleFunc("/chat/internal/broadcast-location", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Internal-Token") != "e2e-internal-token" {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		var bReq struct {
			Channel    string  `json:"channel"`
			Latitude   float64 `json:"latitude"`
			Longitude  float64 `json:"longitude"`
			EmployeeID string  `json:"employee_id"`
		}
		if err := json.NewDecoder(r.Body).Decode(&bReq); err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}

		broadcastPayload, _ := json.Marshal(map[string]any{
			"type":        "location_update",
			"channel":     bReq.Channel,
			"latitude":    bReq.Latitude,
			"longitude":   bReq.Longitude,
			"employee_id": bReq.EmployeeID,
		})

		clientMu.Lock()
		for _, c := range clients {
			if c.channels[bReq.Channel] {
				select {
				case c.send <- broadcastPayload:
				default:
				}
			}
		}
		clientMu.Unlock()

		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "success"})
	})

	mockChatServer := httptest.NewServer(chatMux)
	defer mockChatServer.Close()

	// 2. Setup User Service
	userCfg := &config.Config{
		AuthServiceURL:       mockAuthServer.URL,
		ChatServiceURL:       mockChatServer.URL,
		InternalServiceToken: "e2e-internal-token",
	}
	u := NewUserService(s, userCfg, rdb)

	userMux := http.NewServeMux()
	userMux.HandleFunc("/users/jobs/location/update", u.UpdateJobLocation)
	userMux.HandleFunc("/users/jobs/owner", u.GetOwnerJobs)
	userMux.HandleFunc("/users/jobs/get", u.GetJob)
	userServiceServer := httptest.NewServer(userMux)
	defer userServiceServer.Close()

	// 3. Seed active job and subscription in store
	_ = s.UpsertSubscription(ctx, &models.Subscription{
		TenantID:  ownerID,
		Tier:      models.PlanPaid,
		ExpiresAt: time.Now().Add(30 * 24 * time.Hour),
	})

	jobID := "job-e2e-adr0008"
	job := &models.Job{
		ID:            jobID,
		OwnerID:       ownerID,
		EmployeeID:    empID,
		UserID:        custID,
		ServiceID:     "service-1",
		Status:        models.JobStatusActive,
		Location:      models.Location{Latitude: 30.0449, Longitude: 31.2349},
		PaymentMethod: "cod",
		CreatedAt:     time.Now().Add(-1 * time.Hour),
		UpdatedAt:     time.Now().Add(-1 * time.Hour),
	}
	if err := s.CreateJob(ctx, job); err != nil {
		t.Fatalf("failed to seed job: %v", err)
	}

	// Create JWT Tokens
	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	custToken, _ := jwtutil.GenerateToken(custID, "user", custID, "cust@example.com")
	empToken, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@example.com")

	// 4. Connect Owner WebSocket Client to "fleet:<ownerID>"
	wsURL := fmt.Sprintf("ws%s/chat/ws?token=%s", strings.TrimPrefix(mockChatServer.URL, "http"), ownerToken)
	dialer := websocket.Dialer{}
	header := http.Header{"Origin": []string{"http://localhost:3000"}}

	ownerWS, _, err := dialer.Dial(wsURL, header)
	if err != nil {
		t.Fatalf("Owner WebSocket dial failed: %v", err)
	}
	defer ownerWS.Close()

	if err := ownerWS.WriteJSON(map[string]string{"action": "subscribe", "channel": "fleet:" + ownerID}); err != nil {
		t.Fatalf("Owner subscribe failed: %v", err)
	}

	var ownerSubResp map[string]any
	if err := ownerWS.ReadJSON(&ownerSubResp); err != nil {
		t.Fatalf("Owner read subscribe response failed: %v", err)
	}
	if ownerSubResp["type"] != "subscribed" {
		t.Fatalf("Expected owner subscribed type, got: %v", ownerSubResp)
	}

	// 5. Connect Customer WebSocket Client to "job:<jobID>"
	custWSURL := fmt.Sprintf("ws%s/chat/ws?token=%s", strings.TrimPrefix(mockChatServer.URL, "http"), custToken)
	custWS, _, err := dialer.Dial(custWSURL, header)
	if err != nil {
		t.Fatalf("Customer WebSocket dial failed: %v", err)
	}
	defer custWS.Close()

	if err := custWS.WriteJSON(map[string]string{"action": "subscribe", "channel": "job:" + jobID}); err != nil {
		t.Fatalf("Customer subscribe failed: %v", err)
	}

	var custSubResp map[string]any
	if err := custWS.ReadJSON(&custSubResp); err != nil {
		t.Fatalf("Customer read subscribe response failed: %v", err)
	}
	if custSubResp["type"] != "subscribed" {
		t.Fatalf("Expected customer subscribed type, got: %v", custSubResp)
	}

	// 6. Invoke UpdateJobLocation HTTP endpoint on user-service
	updateReqBody := map[string]any{
		"job_id":          jobID,
		"requester_token": empToken,
		"latitude":        30.045,
		"longitude":       31.235,
	}
	b, _ := json.Marshal(updateReqBody)

	req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+empToken)
	rec := httptest.NewRecorder()

	u.UpdateJobLocation(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("UpdateJobLocation failed with status %d: %s", rec.Code, rec.Body.String())
	}

	// 7. Assert Owner WebSocket receives location_update broadcast on fleet channel
	_ = ownerWS.SetReadDeadline(time.Now().Add(3 * time.Second))
	var ownerMsg map[string]any
	if err := ownerWS.ReadJSON(&ownerMsg); err != nil {
		t.Fatalf("Owner failed to receive location broadcast: %v", err)
	}

	if ownerMsg["type"] != "location_update" {
		t.Fatalf("Expected type location_update, got: %v", ownerMsg["type"])
	}
	if ownerMsg["channel"] != "fleet:"+ownerID {
		t.Fatalf("Expected channel fleet:%s, got: %v", ownerID, ownerMsg["channel"])
	}
	if ownerMsg["employee_id"] != empID {
		t.Fatalf("Expected employee_id %s, got: %v", empID, ownerMsg["employee_id"])
	}
	if lat, ok := ownerMsg["latitude"].(float64); !ok || lat != 30.045 {
		t.Fatalf("Expected latitude 30.045, got: %v", ownerMsg["latitude"])
	}

	// 8. Assert Customer WebSocket receives location_update broadcast on job channel
	_ = custWS.SetReadDeadline(time.Now().Add(3 * time.Second))
	var custMsg map[string]any
	if err := custWS.ReadJSON(&custMsg); err != nil {
		t.Fatalf("Customer failed to receive location broadcast: %v", err)
	}

	if custMsg["type"] != "location_update" {
		t.Fatalf("Expected type location_update for customer, got: %v", custMsg["type"])
	}
	if custMsg["channel"] != "job:"+jobID {
		t.Fatalf("Expected channel job:%s, got: %v", jobID, custMsg["channel"])
	}
	if custMsg["employee_id"] != empID {
		t.Fatalf("Expected employee_id %s, got: %v", empID, custMsg["employee_id"])
	}

	// 9. Verify Initial Hydration logic GET /users/jobs/owner?active_only=true
	ownerHydrateReq := httptest.NewRequest("GET", "/users/jobs/owner?active_only=true", nil)
	ownerHydrateReq.Header.Set("Authorization", "Bearer "+ownerToken)
	ownerHydrateRec := httptest.NewRecorder()

	u.GetOwnerJobs(ownerHydrateRec, ownerHydrateReq)
	if ownerHydrateRec.Code != http.StatusOK {
		t.Fatalf("GetJobsByOwner active_only failed: %d (%s)", ownerHydrateRec.Code, ownerHydrateRec.Body.String())
	}

	var fleetJobs []models.OwnerJobResponse
	if err := json.NewDecoder(ownerHydrateRec.Body).Decode(&fleetJobs); err != nil {
		t.Fatalf("Failed to decode fleet jobs response: %v", err)
	}

	if len(fleetJobs) != 1 {
		t.Fatalf("Expected 1 active fleet job, got %d", len(fleetJobs))
	}
	if fleetJobs[0].ID != jobID {
		t.Fatalf("Expected job ID %s, got %s", jobID, fleetJobs[0].ID)
	}
	if fleetJobs[0].CurrentLocation == nil {
		t.Fatalf("Expected non-nil CurrentLocation after update, got nil")
	}
	if fleetJobs[0].CurrentLocation.Latitude != 30.045 || fleetJobs[0].CurrentLocation.Longitude != 31.235 {
		t.Fatalf("Expected location (30.045, 31.235), got (%f, %f)",
			fleetJobs[0].CurrentLocation.Latitude, fleetJobs[0].CurrentLocation.Longitude)
	}
}
