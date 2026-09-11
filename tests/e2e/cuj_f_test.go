package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"testing"
	"time"
)

// TestCUJ_F_Chat tests the end-to-end real-time chat lifecycle:
// 1. Seed tenant, owner, service, customer, courier A, courier B, and active job
// 2. Customer and Courier A establish real WebSockets through Caddy Gateway reverse proxy
// 3. Customer and Courier A subscribe to job:<job_id> channel
// 4. Customer sends live chat message over WebSocket
// 5. Courier A receives message live over WebSocket
// 6. Query chat history through Gateway -> message order and content persisted
// 7. Negative Guard 1: Unauthorized Courier B querying chat history rejected with 403 Forbidden
// 8. Negative Guard 2: Unauthorized Courier B subscribing to job channel rejected with WebSocket error
func TestCUJ_F_Chat(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-cuj-f-%d", rnd)
	ownerID := tenantID
	serviceID := fmt.Sprintf("svc-cuj-f-%d", rnd)
	courierAID := fmt.Sprintf("courierA-cuj-f-%d", rnd)
	courierBID := fmt.Sprintf("courierB-cuj-f-%d", rnd)
	customerID := fmt.Sprintf("cust-cuj-f-%d", rnd)

	defer func() {
		db.CleanupTestEntities(ctx, []string{tenantID}, []string{ownerID, courierAID, courierBID, customerID})
	}()

	// 1. Seed Tenant, Couriers, Customer, Wallet
	startLat, startLon := 30.0444, 31.2357
	if err := db.SeedTenantAndService(ctx, tenantID, ownerID, serviceID, 20.0, 5.0, startLat, startLon); err != nil {
		t.Fatalf("Failed to seed tenant and service: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantID, courierAID, courierAID+"@staging.local", startLat, startLon); err != nil {
		t.Fatalf("Failed to seed courier A: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantID, courierBID, courierBID+"@staging.local", 30.0500, 31.2400); err != nil {
		t.Fatalf("Failed to seed courier B: %v", err)
	}
	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}
	if err := db.SeedWallet(ctx, tenantID, 500.0); err != nil {
		t.Fatalf("Failed to seed wallet: %v", err)
	}

	custToken, err := cfg.GenerateJWT(customerID, "user", tenantID, customerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate customer token: %v", err)
	}
	courierAToken, err := cfg.GenerateJWT(courierAID, "employee", tenantID, courierAID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate courier A token: %v", err)
	}
	courierBToken, err := cfg.GenerateJWT(courierBID, "employee", tenantID, courierBID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate courier B token: %v", err)
	}

	// Book job and accept to make it active between Customer and Courier A
	bookPayload := map[string]any{
		"service_id":     serviceID,
		"user_id":        custToken,
		"payment_method": "wallet",
		"location": map[string]float64{
			"latitude":  startLat,
			"longitude": startLon,
		},
	}
	resp, body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/track", custToken, bookPayload)
	if err != nil || resp.StatusCode != http.StatusCreated {
		t.Fatalf("Failed to book job: %v, body: %s", err, string(body))
	}
	var bookResp struct {
		JobID string `json:"job_id"`
		Job   struct {
			ID string `json:"id"`
		} `json:"job"`
	}
	_ = json.Unmarshal(body, &bookResp)
	jobID := bookResp.JobID
	if jobID == "" {
		jobID = bookResp.Job.ID
	}

	acceptURL := fmt.Sprintf("%s/api/v1/users/employee/jobs/%s/accept", cfg.GatewayURL, jobID)
	resp, body, err = PostJSON(ctx, acceptURL, courierAToken, nil)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("Failed to accept job: %v, body: %s", err, string(body))
	}
	t.Logf("Job %s is active between customer %s and courier %s", jobID, customerID, courierAID)

	channelName := "job:" + jobID

	// 2. Establish real WebSockets for Customer and Courier A
	custWS, err := ConnectWS(ctx, cfg.GatewayURL, custToken)
	if err != nil {
		t.Fatalf("Customer failed to connect WebSocket: %v", err)
	}
	defer custWS.Close()

	courierWS, err := ConnectWS(ctx, cfg.GatewayURL, courierAToken)
	if err != nil {
		t.Fatalf("Courier A failed to connect WebSocket: %v", err)
	}
	defer courierWS.Close()

	// 3. Subscribe to job channel
	subMsg := map[string]string{
		"action":  "subscribe",
		"channel": channelName,
	}
	if err := custWS.Send(subMsg); err != nil {
		t.Fatalf("Customer failed to send subscribe action: %v", err)
	}
	if err := courierWS.Send(subMsg); err != nil {
		t.Fatalf("Courier failed to send subscribe action: %v", err)
	}

	// Verify Customer subscription confirmation
	_, err = custWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		return m["type"] == "subscribed" && m["channel"] == channelName
	})
	if err != nil {
		t.Fatalf("Customer did not receive subscription confirmation: %v", err)
	}

	// Verify Courier subscription confirmation
	_, err = courierWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		return m["type"] == "subscribed" && m["channel"] == channelName
	})
	if err != nil {
		t.Fatalf("Courier did not receive subscription confirmation: %v", err)
	}
	t.Logf("Customer and Courier A subscribed to %s successfully", channelName)

	// 4. Customer sends live chat message over WebSocket
	testMsgContent := "Hello courier, I am waiting at the front entrance."
	chatMsg := map[string]string{
		"action":  "message",
		"channel": channelName,
		"content": testMsgContent,
	}
	if err := custWS.Send(chatMsg); err != nil {
		t.Fatalf("Customer failed to send chat message: %v", err)
	}

	// 5. Courier A receives message live over WebSocket
	incoming, err := courierWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		return m["channel"] == channelName && m["type"] == "message"
	})
	if err != nil {
		t.Fatalf("Courier A failed to receive live chat message: %v", err)
	}
	if incoming["content"] != testMsgContent {
		t.Fatalf("Expected content %q, got %v", testMsgContent, incoming["content"])
	}
	t.Logf("Verified: Courier A received live message over WebSocket: %s", incoming["content"])

	// 6. Query chat history through Gateway -> message order and content persisted
	historyURL := fmt.Sprintf("%s/api/v1/chat/history?channel=%s&token=%s", cfg.GatewayURL, channelName, custToken)
	resp, body, err = GetJSON(ctx, historyURL, custToken)
	if err != nil {
		t.Fatalf("Failed to query chat history: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from chat history, got %d: %s", resp.StatusCode, string(body))
	}

	var history []struct {
		SenderID string `json:"sender_id"`
		Content  string `json:"content"`
		Channel  string `json:"channel"`
	}
	if err := json.Unmarshal(body, &history); err != nil {
		t.Fatalf("Failed to parse chat history: %v", err)
	}
	if len(history) == 0 {
		t.Fatalf("ASSERTION FAILED: Chat history is empty, expected persisted message")
	}
	found := false
	for _, h := range history {
		if h.Content == testMsgContent && h.SenderID == customerID {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("ASSERTION FAILED: Persisted message not found in history: %s", string(body))
	}
	t.Logf("Verified: Chat message persisted in MongoDB and retrieved via history: %d messages", len(history))

	// 7. Negative Guard 1: Unauthorized Courier B querying chat history rejected with 403 Forbidden
	idorHistoryURL := fmt.Sprintf("%s/api/v1/chat/history?channel=%s&token=%s", cfg.GatewayURL, channelName, courierBToken)
	resp, body, err = GetJSON(ctx, idorHistoryURL, courierBToken)
	if err != nil {
		t.Fatalf("Failed to query IDOR chat history: %v", err)
	}
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("ASSERTION FAILED: Courier B querying job chat history must return 403 Forbidden, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified Negative Guard 1: Unauthorized Courier B denied chat history with 403 Forbidden")

	// 8. Negative Guard 2: Unauthorized Courier B subscribing to job channel rejected with WebSocket error
	courierBWS, err := ConnectWS(ctx, cfg.GatewayURL, courierBToken)
	if err != nil {
		t.Fatalf("Courier B failed to connect WebSocket: %v", err)
	}
	defer courierBWS.Close()

	if err := courierBWS.Send(subMsg); err != nil {
		t.Fatalf("Courier B failed to send subscribe action: %v", err)
	}

	wsErr, err := courierBWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		return m["type"] == "error" && m["channel"] == channelName
	})
	if err != nil {
		t.Fatalf("Courier B expected WebSocket authorization error, got: %v", err)
	}
	t.Logf("Verified Negative Guard 2: Unauthorized Courier B subscription rejected over WebSocket: %+v", wsErr)
	t.Logf("== CUJ-F (Active Job Real-Time Chat & IDOR Isolation) PASSED CLEANLY ==")
}
