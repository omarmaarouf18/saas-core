package e2e

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/project/shared/infra/jwtutil"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

type Config struct {
	GatewayURL string
	ConsoleURL string
	MongoURI   string
	JWTSecret  string
}

func LoadConfig() *Config {
	cfg := &Config{
		GatewayURL: os.Getenv("STAGING_GATEWAY_URL"),
		ConsoleURL: os.Getenv("STAGING_CONSOLE_URL"),
		MongoURI:   os.Getenv("STAGING_MONGO_URI"),
		JWTSecret:  os.Getenv("JWT_SECRET"),
	}
	if cfg.GatewayURL == "" {
		cfg.GatewayURL = "http://localhost:8088"
	}
	if cfg.ConsoleURL == "" {
		cfg.ConsoleURL = "http://localhost:8091"
	}
	if cfg.MongoURI == "" {
		cfg.MongoURI = "mongodb://staging_root:staging_secret123@localhost:27018/?authSource=admin"
	}
	if cfg.JWTSecret == "" {
		cfg.JWTSecret = "NrrYbDqT4bRD/ADvJ5U2VKmLqXr8nk21IRVAbrzVI1mqEhuMhII3IO26PPa4qJtR"
	}
	jwtutil.Init(cfg.JWTSecret)
	return cfg
}

func (c *Config) GenerateJWT(userID, role, tenantID, email string) (string, error) {
	return jwtutil.GenerateToken(userID, role, tenantID, email)
}

// ---------------------------------------------------------------------------
// Real SSE Subscription Client (Traverses Caddy -> API Gateway -> Service)
// ---------------------------------------------------------------------------

type SSEEvent struct {
	Event string
	Data  string
	ID    string
}

type SSESubscription struct {
	Events chan SSEEvent
	cancel context.CancelFunc
	resp   *http.Response
	closed bool
	mu     sync.Mutex
}

func ConnectSSE(ctx context.Context, gatewayURL, token string) (*SSESubscription, error) {
	streamCtx, streamCancel := context.WithCancel(ctx)
	targetURL := fmt.Sprintf("%s/api/v1/notifications/stream?token=%s", strings.TrimSuffix(gatewayURL, "/"), url.QueryEscape(token))
	req, err := http.NewRequestWithContext(streamCtx, "GET", targetURL, nil)
	if err != nil {
		streamCancel()
		return nil, fmt.Errorf("failed to build SSE request: %w", err)
	}

	client := &http.Client{Timeout: 0}
	resp, err := client.Do(req)
	if err != nil {
		streamCancel()
		return nil, fmt.Errorf("failed to connect to SSE stream: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		streamCancel()
		return nil, fmt.Errorf("SSE stream returned HTTP %d: %s", resp.StatusCode, string(body))
	}

	sub := &SSESubscription{
		Events: make(chan SSEEvent, 50),
		cancel: streamCancel,
		resp:   resp,
	}

	go sub.readLoop()
	return sub, nil
}

func (s *SSESubscription) readLoop() {
	defer func() {
		s.mu.Lock()
		s.closed = true
		s.mu.Unlock()
		_ = s.resp.Body.Close()
		close(s.Events)
	}()

	reader := bufio.NewReader(s.resp.Body)
	var currentEvent SSEEvent

	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			return
		}

		trimmed := strings.TrimRight(line, "\r\n")
		if trimmed == "" {
			// Dispatch event if there is any data or event name
			if currentEvent.Event != "" || currentEvent.Data != "" {
				s.Events <- currentEvent
				currentEvent = SSEEvent{}
			}
			continue
		}

		if strings.HasPrefix(trimmed, "event:") {
			currentEvent.Event = strings.TrimSpace(strings.TrimPrefix(trimmed, "event:"))
		} else if strings.HasPrefix(trimmed, "data:") {
			dataPart := strings.TrimSpace(strings.TrimPrefix(trimmed, "data:"))
			if currentEvent.Data == "" {
				currentEvent.Data = dataPart
			} else {
				currentEvent.Data += "\n" + dataPart
			}
		} else if strings.HasPrefix(trimmed, "id:") {
			currentEvent.ID = strings.TrimSpace(strings.TrimPrefix(trimmed, "id:"))
		}
	}
}

func (s *SSESubscription) WaitForEvent(timeout time.Duration, filter func(e SSEEvent) bool) (*SSEEvent, error) {
	deadline := time.After(timeout)
	for {
		select {
		case ev, ok := <-s.Events:
			if !ok {
				return nil, fmt.Errorf("SSE stream closed while waiting for event")
			}
			if filter(ev) {
				return &ev, nil
			}
		case <-deadline:
			return nil, fmt.Errorf("timeout waiting for SSE event")
		}
	}
}

func (s *SSESubscription) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.closed {
		s.cancel()
		_ = s.resp.Body.Close()
	}
}

// ---------------------------------------------------------------------------
// Real WebSocket Client (Traverses Caddy -> API Gateway -> chat-service)
// ---------------------------------------------------------------------------

type WSClient struct {
	Conn     *websocket.Conn
	Messages chan map[string]any
	cancel   context.CancelFunc
	closed   bool
	mu       sync.Mutex
}

func ConnectWS(ctx context.Context, gatewayURL, token string) (*WSClient, error) {
	wsCtx, wsCancel := context.WithCancel(ctx)
	u, err := url.Parse(gatewayURL)
	if err != nil {
		wsCancel()
		return nil, fmt.Errorf("invalid gateway url: %w", err)
	}

	scheme := "ws"
	if u.Scheme == "https" {
		scheme = "wss"
	}
	wsTarget := fmt.Sprintf("%s://%s/api/v1/chat/ws?token=%s", scheme, u.Host, url.QueryEscape(token))

	dialer := websocket.Dialer{
		HandshakeTimeout: 10 * time.Second,
	}
	conn, resp, err := dialer.DialContext(wsCtx, wsTarget, nil)
	if err != nil {
		wsCancel()
		status := 0
		if resp != nil {
			status = resp.StatusCode
		}
		return nil, fmt.Errorf("WebSocket dial failed (status %d): %w", status, err)
	}

	client := &WSClient{
		Conn:     conn,
		Messages: make(chan map[string]any, 50),
		cancel:   wsCancel,
	}

	go client.readLoop()
	return client, nil
}

func (c *WSClient) readLoop() {
	defer func() {
		c.mu.Lock()
		c.closed = true
		c.mu.Unlock()
		_ = c.Conn.Close()
		close(c.Messages)
	}()

	for {
		_, messageBytes, err := c.Conn.ReadMessage()
		if err != nil {
			return
		}

		var payload map[string]any
		if err := json.Unmarshal(messageBytes, &payload); err == nil {
			c.Messages <- payload
		}
	}
}

func (c *WSClient) Send(msg any) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.Conn.WriteJSON(msg)
}

func (c *WSClient) WaitForMessage(timeout time.Duration, filter func(m map[string]any) bool) (map[string]any, error) {
	deadline := time.After(timeout)
	for {
		select {
		case msg, ok := <-c.Messages:
			if !ok {
				return nil, fmt.Errorf("WebSocket connection closed")
			}
			if filter(msg) {
				return msg, nil
			}
		case <-deadline:
			return nil, fmt.Errorf("timeout waiting for WebSocket message")
		}
	}
}

func (c *WSClient) Close() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.closed {
		c.cancel()
		_ = c.Conn.Close()
	}
}

// ---------------------------------------------------------------------------
// Staging Database Seeding & Verification Helper
// ---------------------------------------------------------------------------

type StagingDB struct {
	client *mongo.Client
}

func ConnectStagingDB(ctx context.Context, mongoURI string) (*StagingDB, error) {
	opts := options.Client().ApplyURI(mongoURI)
	client, err := mongo.Connect(opts)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to staging mongo: %w", err)
	}
	if err := client.Ping(ctx, nil); err != nil {
		return nil, fmt.Errorf("failed to ping staging mongo: %w", err)
	}
	return &StagingDB{client: client}, nil
}

func (db *StagingDB) Close(ctx context.Context) {
	_ = db.client.Disconnect(ctx)
}

func (db *StagingDB) SeedTenantAndService(ctx context.Context, tenantID, ownerID, serviceID string, basePrice, pricePerKM, lat, lon float64) error {
	// 1. Owner in auth_db.users
	authUsers := db.client.Database("staging_auth_db").Collection("users")
	_, err := authUsers.UpdateOne(
		ctx,
		bson.M{"_id": ownerID},
		bson.M{
			"$set": bson.M{
				"_id":            ownerID,
				"username":       "owner_" + ownerID,
				"email":          ownerID + "@staging.local",
				"role":           "owner",
				"tenant_id":      tenantID,
				"is_active":      true,
				"kyc_status":     "approved",
				"account_status": "active",
				"updated_at":     time.Now().UTC(),
			},
			"$setOnInsert": bson.M{
				"created_at": time.Now().UTC(),
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	if err != nil {
		return fmt.Errorf("failed to upsert owner: %w", err)
	}

	// 2. Paid Subscription in user_db.subscriptions
	userSubs := db.client.Database("staging_user_db").Collection("subscriptions")
	_, err = userSubs.UpdateOne(
		ctx,
		bson.M{"_id": tenantID},
		bson.M{
			"$set": bson.M{
				"_id":        tenantID,
				"tenant_id":  tenantID,
				"tier":       "paid",
				"plan":       "paid",
				"status":     "active",
				"expires_at": time.Now().UTC().Add(365 * 24 * time.Hour),
				"updated_at": time.Now().UTC(),
			},
			"$setOnInsert": bson.M{
				"created_at": time.Now().UTC(),
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	if err != nil {
		return fmt.Errorf("failed to upsert subscription: %w", err)
	}

	// 3. Service in user_db.services
	userServices := db.client.Database("staging_user_db").Collection("services")
	_, err = userServices.UpdateOne(
		ctx,
		bson.M{"_id": serviceID},
		bson.M{
			"$set": bson.M{
				"_id":                 serviceID,
				"tenant_id":           tenantID,
				"owner_id":            ownerID,
				"name":                "Express Delivery Service",
				"category":            "delivery",
				"tenant_base_price":   basePrice,
				"tenant_price_per_km": pricePerKM,
				"latitude":            lat,
				"longitude":           lon,
				"coverage_radius_km":  50.0,
				"is_active":           true,
				"location": bson.M{
					"type":        "Point",
					"coordinates": []float64{lon, lat},
				},
				"updated_at": time.Now().UTC(),
			},
			"$setOnInsert": bson.M{
				"created_at": time.Now().UTC(),
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	if err != nil {
		return fmt.Errorf("failed to upsert service: %w", err)
	}

	return nil
}

func (db *StagingDB) SeedCourier(ctx context.Context, tenantID, courierID, email string, lat, lon float64) error {
	// 1. Employee in auth_db.users
	authUsers := db.client.Database("staging_auth_db").Collection("users")
	_, err := authUsers.UpdateOne(
		ctx,
		bson.M{"_id": courierID},
		bson.M{
			"$set": bson.M{
				"_id":            courierID,
				"username":       "courier_" + courierID,
				"email":          email,
				"role":           "employee",
				"tenant_id":      tenantID,
				"is_active":      true,
				"account_status": "active",
				"updated_at":     time.Now().UTC(),
			},
			"$setOnInsert": bson.M{
				"created_at": time.Now().UTC(),
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	if err != nil {
		return fmt.Errorf("failed to upsert courier: %w", err)
	}

	// 2. Active location in user_db.employee_locations
	empLocs := db.client.Database("staging_user_db").Collection("employee_locations")
	_, err = empLocs.UpdateOne(
		ctx,
		bson.M{"_id": courierID},
		bson.M{
			"$set": bson.M{
				"_id":         courierID,
				"employee_id": courierID,
				"tenant_id":   tenantID,
				"latitude":    lat,
				"longitude":   lon,
				"is_online":   true,
				"updated_at":  time.Now().UTC(),
				"location": bson.M{
					"type":        "Point",
					"coordinates": []float64{lon, lat},
				},
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	if err != nil {
		return fmt.Errorf("failed to upsert courier location: %w", err)
	}

	return nil
}

func (db *StagingDB) SeedCustomer(ctx context.Context, tenantID, customerID, email string) error {
	authUsers := db.client.Database("staging_auth_db").Collection("users")
	_, err := authUsers.UpdateOne(
		ctx,
		bson.M{"_id": customerID},
		bson.M{
			"$set": bson.M{
				"_id":            customerID,
				"username":       "cust_" + customerID,
				"email":          email,
				"role":           "user",
				"tenant_id":      tenantID,
				"is_active":      true,
				"account_status": "active",
				"updated_at":     time.Now().UTC(),
			},
			"$setOnInsert": bson.M{
				"created_at": time.Now().UTC(),
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	return err
}

func (db *StagingDB) SeedWallet(ctx context.Context, tenantID string, initialBalance float64) error {
	wallets := db.client.Database("staging_user_db").Collection("wallets")
	_, err := wallets.UpdateOne(
		ctx,
		bson.M{"tenant_id": tenantID},
		bson.M{
			"$set": bson.M{
				"_id":                  tenantID,
				"tenant_id":            tenantID,
				"total_balance":        initialBalance,
				"escrow_balance":       0.0,
				"withdrawable_balance": initialBalance,
				"updated_at":           time.Now().UTC(),
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	return err
}

func (db *StagingDB) SeedReviewer(ctx context.Context, reviewerID, name, rawToken string) error {
	h := sha256.Sum256([]byte(rawToken))
	tokenDigest := hex.EncodeToString(h[:])

	reviewers := db.client.Database("staging_auth_db").Collection("reviewers")
	_, err := reviewers.UpdateOne(
		ctx,
		bson.M{"_id": reviewerID},
		bson.M{
			"$set": bson.M{
				"_id":        reviewerID,
				"name":       name,
				"token":      tokenDigest,
				"created_at": time.Now().UTC(),
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	return err
}

func (db *StagingDB) SeedKYCSubmission(ctx context.Context, userID, email, role, tenantID string) error {
	authUsers := db.client.Database("staging_auth_db").Collection("users")
	_, err := authUsers.UpdateOne(
		ctx,
		bson.M{"_id": userID},
		bson.M{
			"$set": bson.M{
				"_id":                userID,
				"username":           "kyc_user_" + userID,
				"email":              email,
				"role":               role,
				"tenant_id":          tenantID,
				"is_active":          true,
				"account_status":     "active",
				"kyc_status":         "pending_super_admin_approval",
				"id_front_doc":       "kyb/" + userID + "/id_front.png",
				"id_back_doc":        "kyb/" + userID + "/id_back.png",
				"selfie_doc":         "kyb/" + userID + "/selfie.png",
				"business_proof_doc": "kyb/" + userID + "/proof.pdf",
				"rejection_reason":   "",
				"updated_at":         time.Now().UTC(),
			},
			"$setOnInsert": bson.M{
				"created_at": time.Now().UTC(),
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	return err
}

func (db *StagingDB) SeedFreeSubscription(ctx context.Context, tenantID string) error {
	userSubs := db.client.Database("staging_user_db").Collection("subscriptions")
	_, err := userSubs.UpdateOne(
		ctx,
		bson.M{"_id": tenantID},
		bson.M{
			"$set": bson.M{
				"_id":        tenantID,
				"tenant_id":  tenantID,
				"tier":       "free",
				"plan":       "free",
				"status":     "active",
				"updated_at": time.Now().UTC(),
			},
			"$setOnInsert": bson.M{
				"created_at": time.Now().UTC(),
			},
		},
		options.UpdateOne().SetUpsert(true),
	)
	return err
}

func (db *StagingDB) CleanupTestEntities(ctx context.Context, tenantIDs, userIDs []string) {
	_, _ = db.client.Database("staging_auth_db").Collection("users").DeleteMany(ctx, bson.M{"_id": bson.M{"$in": userIDs}})
	_, _ = db.client.Database("staging_auth_db").Collection("pending_signups").DeleteMany(ctx, bson.M{"email": bson.M{"$in": userIDs}})
	_, _ = db.client.Database("staging_user_db").Collection("employee_locations").DeleteMany(ctx, bson.M{"_id": bson.M{"$in": userIDs}})
	_, _ = db.client.Database("staging_user_db").Collection("services").DeleteMany(ctx, bson.M{"tenant_id": bson.M{"$in": tenantIDs}})
	_, _ = db.client.Database("staging_user_db").Collection("subscriptions").DeleteMany(ctx, bson.M{"_id": bson.M{"$in": tenantIDs}})
	_, _ = db.client.Database("staging_user_db").Collection("wallets").DeleteMany(ctx, bson.M{"tenant_id": bson.M{"$in": tenantIDs}})
	_, _ = db.client.Database("staging_user_db").Collection("ledger").DeleteMany(ctx, bson.M{"tenant_id": bson.M{"$in": tenantIDs}})
	_, _ = db.client.Database("staging_user_db").Collection("jobs").DeleteMany(ctx, bson.M{"tenant_id": bson.M{"$in": tenantIDs}})
	_, _ = db.client.Database("staging_user_db").Collection("ratings").DeleteMany(ctx, bson.M{"$or": []bson.M{{"rated_by": bson.M{"$in": userIDs}}, {"rated_user": bson.M{"$in": userIDs}}}})
	_, _ = db.client.Database("staging_chat_db").Collection("complaint_tickets").DeleteMany(ctx, bson.M{"customer_id": bson.M{"$in": userIDs}})
	_, _ = db.client.Database("staging_chat_db").Collection("messages").DeleteMany(ctx, bson.M{"sender_id": bson.M{"$in": userIDs}})
	_, _ = db.client.Database("staging_notification_db").Collection("notifications").DeleteMany(ctx, bson.M{"tenant_id": bson.M{"$in": tenantIDs}})
}

func DoJSONRequest(ctx context.Context, method, targetURL, token string, body any) (*http.Response, []byte, error) {
	var bodyReader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, nil, err
		}
		bodyReader = bytes.NewReader(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, targetURL, bodyReader)
	if err != nil {
		return nil, nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	return resp, respBody, err
}

func PostJSON(ctx context.Context, targetURL, token string, body any) (*http.Response, []byte, error) {
	return DoJSONRequest(ctx, http.MethodPost, targetURL, token, body)
}

func PutJSON(ctx context.Context, targetURL, token string, body any) (*http.Response, []byte, error) {
	return DoJSONRequest(ctx, http.MethodPut, targetURL, token, body)
}

func PatchJSON(ctx context.Context, targetURL, token string, body any) (*http.Response, []byte, error) {
	return DoJSONRequest(ctx, http.MethodPatch, targetURL, token, body)
}

func DeleteJSON(ctx context.Context, targetURL, token string) (*http.Response, []byte, error) {
	return DoJSONRequest(ctx, http.MethodDelete, targetURL, token, nil)
}

func GetJSON(ctx context.Context, targetURL, token string) (*http.Response, []byte, error) {
	return DoJSONRequest(ctx, http.MethodGet, targetURL, token, nil)
}
