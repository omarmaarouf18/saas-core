package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"strings"
	"testing"
	"time"
)

// TestCUJ_H_SupportTicketResolution tests the dual-delivery regression guard for ticket resolution:
// 1. Seed Customer and Reviewer credentials in staging database
// 2. Customer establishes live SSE stream through Caddy -> API Gateway -> notification-service
// 3. Customer creates a support ticket via POST /api/v1/chat/tickets
// 4. Customer establishes live WebSocket and subscribes to ticket:<ticket_id> channel
// 5. Negative Guard 1: Reviewer submitting empty resolution note rejected with 400 Bad Request
// 6. Reviewer resolves ticket via Reviewer Console (POST /api/tickets/resolve on :8091)
// 7. DUAL-DELIVERY ASSERTION 1: Customer receives live SSE notification (type: "ticket_resolved")
// 8. DUAL-DELIVERY ASSERTION 2: Customer receives live system message in WebSocket channel (ticket:<id>)
// 9. Negative Guard 2: Non-reviewer attempting resolution rejected with 401 Unauthorized
func TestCUJ_H_SupportTicketResolution(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-cuj-h-%d", rnd)
	customerID := fmt.Sprintf("cust-cuj-h-%d", rnd)
	reviewerID := fmt.Sprintf("rev-cuj-h-%d", rnd)
	rawReviewerToken := fmt.Sprintf("reviewer-secret-token-%d", rnd)

	defer func() {
		db.CleanupTestEntities(ctx, []string{tenantID}, []string{customerID})
		_, _ = db.client.Database("staging_auth_db").Collection("reviewers").DeleteOne(ctx, map[string]any{"_id": reviewerID})
	}()

	// 1. Seed Customer and Reviewer
	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}
	if err := db.SeedReviewer(ctx, reviewerID, "QA Ops Reviewer", rawReviewerToken); err != nil {
		t.Fatalf("Failed to seed reviewer: %v", err)
	}

	custToken, err := cfg.GenerateJWT(customerID, "user", tenantID, customerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate customer token: %v", err)
	}

	// 2. Customer connects live SSE stream
	custSSE, err := ConnectSSE(ctx, cfg.GatewayURL, custToken)
	if err != nil {
		t.Fatalf("Customer failed to connect SSE stream: %v", err)
	}
	defer custSSE.Close()

	_, err = custSSE.WaitForEvent(5*time.Second, func(e SSEEvent) bool { return e.Event == "connected" })
	if err != nil {
		t.Fatalf("Customer SSE did not receive initial handshake: %v", err)
	}
	t.Logf("Customer SSE connected successfully through Gateway reverse proxy")

	// 3. Customer creates support ticket
	ticketPayload := map[string]string{
		"context_id": fmt.Sprintf("job-issue-%d", rnd),
	}
	resp, body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/chat/tickets", custToken, ticketPayload)
	if err != nil {
		t.Fatalf("Customer failed to create ticket: %v", err)
	}
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("Expected 201 Created from ticket creation, got %d: %s", resp.StatusCode, string(body))
	}

	var ticketResp struct {
		ID         string `json:"ticket_id"`
		CustomerID string `json:"customer_id"`
		Status     string `json:"status"`
	}
	if err := json.Unmarshal(body, &ticketResp); err != nil {
		t.Fatalf("Failed to parse ticket response: %v", err)
	}
	ticketID := ticketResp.ID
	if ticketID == "" {
		t.Fatalf("Expected non-empty ticket ID, got: %s", string(body))
	}
	t.Logf("Customer created support ticket %s successfully (status=%s)", ticketID, ticketResp.Status)

	// 4. Customer connects WebSocket and subscribes to ticket channel
	custWS, err := ConnectWS(ctx, cfg.GatewayURL, custToken)
	if err != nil {
		t.Fatalf("Customer failed to connect WebSocket: %v", err)
	}
	defer custWS.Close()

	ticketChannel := "ticket:" + ticketID
	subMsg := map[string]string{
		"action":  "subscribe",
		"channel": ticketChannel,
	}
	if err := custWS.Send(subMsg); err != nil {
		t.Fatalf("Customer failed to subscribe to ticket channel: %v", err)
	}

	_, err = custWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		return m["type"] == "subscribed" && m["channel"] == ticketChannel
	})
	if err != nil {
		t.Fatalf("Customer did not receive ticket channel subscription confirmation: %v", err)
	}
	t.Logf("Customer subscribed to %s over WebSocket successfully", ticketChannel)

	resolveURL := cfg.ConsoleURL + "/api/tickets/resolve"

	// 5. Negative Guard 1: Empty resolution note rejected with 400 Bad Request
	emptyNotePayload := map[string]string{
		"ticket_id":       ticketID,
		"resolution_note": "",
	}
	emptyBodyBytes, _ := json.Marshal(emptyNotePayload)
	emptyReq, _ := http.NewRequestWithContext(ctx, http.MethodPost, resolveURL, bytes.NewReader(emptyBodyBytes))
	emptyReq.Header.Set("Content-Type", "application/json")
	emptyReq.Header.Set("X-Reviewer-Token", rawReviewerToken)

	emptyResp, err := http.DefaultClient.Do(emptyReq)
	if err != nil {
		t.Fatalf("Failed to send empty note resolve request: %v", err)
	}
	defer emptyResp.Body.Close()
	if emptyResp.StatusCode != http.StatusBadRequest {
		t.Fatalf("ASSERTION FAILED: Empty resolution note should return 400 Bad Request, got %d", emptyResp.StatusCode)
	}
	t.Logf("Verified Negative Guard 1: Empty resolution note rejected with 400 Bad Request")

	// 6. Reviewer resolves ticket with valid note
	validNote := "Investigated customer dispatch log. Refund credit applied to wallet."
	validResolvePayload := map[string]string{
		"ticket_id":       ticketID,
		"resolution_note": validNote,
	}
	validBodyBytes, _ := json.Marshal(validResolvePayload)
	validReq, _ := http.NewRequestWithContext(ctx, http.MethodPost, resolveURL, bytes.NewReader(validBodyBytes))
	validReq.Header.Set("Content-Type", "application/json")
	validReq.Header.Set("X-Reviewer-Token", rawReviewerToken)

	validResp, err := http.DefaultClient.Do(validReq)
	if err != nil {
		t.Fatalf("Failed to send valid resolve request: %v", err)
	}
	defer validResp.Body.Close()
	validRespBytes, _ := io.ReadAll(validResp.Body)
	if validResp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from reviewer console resolve, got %d: %s", validResp.StatusCode, string(validRespBytes))
	}
	t.Logf("Verified: Reviewer console resolved ticket %s with 200 OK: %s", ticketID, string(validRespBytes))

	// 7. DUAL-DELIVERY ASSERTION 1: Customer receives live SSE notification
	sseEv, err := custSSE.WaitForEvent(5*time.Second, func(e SSEEvent) bool {
		return strings.Contains(e.Data, "ticket_resolved") || strings.Contains(e.Data, ticketID)
	})
	if err != nil {
		t.Fatalf("DUAL-DELIVERY FAILURE (SSE): Customer did not receive ticket_resolved SSE event: %v", err)
	}
	t.Logf("Verified Dual-Delivery [1/2 SSE]: Customer received live SSE resolution notification: %s", sseEv.Data)
	if !strings.Contains(sseEv.Data, "ticket_resolved") {
		t.Errorf("Expected 'ticket_resolved' in SSE data, got: %s", sseEv.Data)
	}

	// 8. DUAL-DELIVERY ASSERTION 2: Customer receives live system message in WebSocket channel
	wsMsg, err := custWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		ch, _ := m["channel"].(string)
		content, _ := m["content"].(string)
		return ch == ticketChannel && strings.Contains(content, validNote)
	})
	if err != nil {
		t.Fatalf("DUAL-DELIVERY FAILURE (WebSocket): Customer did not receive resolution message in %s: %v", ticketChannel, err)
	}
	t.Logf("Verified Dual-Delivery [2/2 WebSocket]: Customer received live resolution message in ticket channel: %+v", wsMsg)

	// 9. Negative Guard 2: Non-reviewer attempting resolution rejected with 401
	unauthPayload := map[string]string{
		"ticket_id":       ticketID,
		"resolution_note": "Attempted resolution by attacker",
	}
	unauthBodyBytes, _ := json.Marshal(unauthPayload)
	unauthReq, _ := http.NewRequestWithContext(ctx, http.MethodPost, resolveURL, bytes.NewReader(unauthBodyBytes))
	unauthReq.Header.Set("Content-Type", "application/json")
	unauthReq.Header.Set("X-Reviewer-Token", "invalid-fake-token")

	unauthResp, err := http.DefaultClient.Do(unauthReq)
	if err != nil {
		t.Fatalf("Failed to send unauthorized resolve request: %v", err)
	}
	defer unauthResp.Body.Close()
	if unauthResp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("ASSERTION FAILED: Non-reviewer resolve should return 401, got %d", unauthResp.StatusCode)
	}
	t.Logf("Verified Negative Guard 2: Non-reviewer resolution rejected with 401 Unauthorized")
	t.Logf("== CUJ-H (Support Ticket Resolution & Dual-Delivery Regression Guard) PASSED CLEANLY ==")
}
