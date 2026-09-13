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

// TestCUJ_I_SupportTicketLifecycle tests the complete support ticket flow:
// 1. Seed Customer and two Reviewers in staging database
// 2. Customer creates support ticket (status: "pending", unassigned)
// 3. Reviewer 1 views pending ticket in Reviewer Console (GET /api/tickets on :8091)
// 4. Customer establishes live SSE notifications and WebSocket connection to ticket channel
// 5. Reviewer 1 accepts ticket via Reviewer Console (POST /api/tickets/accept -> status: "assigned")
// 6. CAS Concurrency Guard: Reviewer 2 attempts to accept already-assigned ticket -> 409 Conflict
// 7. Dual-Delivery on Accept: Customer receives live SSE "ticket_assigned" and WS system message
// 8. Reviewer 1 establishes live WebSocket connection via Console (/api/chat/ws on :8091)
// 9. Two-way real-time chat: Reviewer sends message -> Customer receives on WS; Customer replies -> Reviewer receives on WS
// 10. Reviewer 1 resolves ticket with resolution note via Reviewer Console (POST /api/tickets/resolve)
// 11. Dual-Delivery on Resolve: Customer receives live SSE "ticket_resolved" and WS resolution message
// 12. Final status verification in Reviewer Console (status: "resolved", resolved_by verified)
func TestCUJ_I_SupportTicketLifecycle(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 35*time.Second)
	defer cancel()

	cfg := LoadConfig()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-cuj-i-%d", rnd)
	customerID := fmt.Sprintf("cust-cuj-i-%d", rnd)
	reviewer1ID := fmt.Sprintf("rev-1-cuj-i-%d", rnd)
	reviewer2ID := fmt.Sprintf("rev-2-cuj-i-%d", rnd)
	rawReviewerToken1 := fmt.Sprintf("reviewer1-token-%d", rnd)
	rawReviewerToken2 := fmt.Sprintf("reviewer2-token-%d", rnd)

	_ = FlushReviewerRateLimits(ctx, cfg.RedisURI)
	defer func() {
		_ = FlushReviewerRateLimits(ctx, cfg.RedisURI)
		db.CleanupTestEntities(ctx, []string{tenantID}, []string{customerID})
		_, _ = db.client.Database("staging_auth_db").Collection("reviewers").DeleteMany(ctx, map[string]any{
			"_id": map[string]any{"$in": []string{reviewer1ID, reviewer2ID}},
		})
	}()

	// 1. Seed Customer and two Reviewers
	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}
	if err := db.SeedReviewer(ctx, reviewer1ID, "Alice Ops", rawReviewerToken1); err != nil {
		t.Fatalf("Failed to seed reviewer 1: %v", err)
	}
	if err := db.SeedReviewer(ctx, reviewer2ID, "Bob Ops", rawReviewerToken2); err != nil {
		t.Fatalf("Failed to seed reviewer 2: %v", err)
	}

	custToken, err := cfg.GenerateJWT(customerID, "user", tenantID, customerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate customer token: %v", err)
	}

	// 2. Customer creates support ticket -> must start as "pending" with no assigned reviewer
	ticketPayload := map[string]string{
		"context_id": fmt.Sprintf("order-incident-%d", rnd),
	}
	resp, body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/chat/tickets", custToken, ticketPayload)
	if err != nil {
		t.Fatalf("Customer failed to create ticket: %v", err)
	}
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("Expected 201 Created from ticket creation, got %d: %s", resp.StatusCode, string(body))
	}

	var createTicketResp struct {
		TicketID         string `json:"ticket_id"`
		CustomerID       string `json:"customer_id"`
		Status           string `json:"status"`
		AssignedAgentID  string `json:"assigned_agent_id"`
		AssignedReviewer string `json:"assigned_reviewer"`
	}
	if err := json.Unmarshal(body, &createTicketResp); err != nil {
		t.Fatalf("Failed to parse ticket creation response: %v", err)
	}
	ticketID := createTicketResp.TicketID
	if ticketID == "" {
		t.Fatalf("Expected non-empty ticket ID, got: %s", string(body))
	}
	if createTicketResp.Status != "pending" {
		t.Fatalf("ASSERTION FAILED: New ticket status must be 'pending', got: %s", createTicketResp.Status)
	}
	if createTicketResp.AssignedAgentID != "" || createTicketResp.AssignedReviewer != "" {
		t.Fatalf("ASSERTION FAILED: New ticket must not have an assigned agent/reviewer, got agent=%q reviewer=%q",
			createTicketResp.AssignedAgentID, createTicketResp.AssignedReviewer)
	}
	t.Logf("Step 1 PASSED: Ticket %s created with status='pending' (unassigned)", ticketID)

	// 3. Reviewer 1 lists tickets via Reviewer Console (GET /api/tickets on :8091)
	reqList, _ := http.NewRequestWithContext(ctx, http.MethodGet, cfg.ConsoleURL+"/api/tickets", nil)
	reqList.Header.Set("X-Reviewer-Token", rawReviewerToken1)
	respList, err := http.DefaultClient.Do(reqList)
	if err != nil {
		t.Fatalf("Reviewer 1 failed to list tickets: %v", err)
	}
	defer respList.Body.Close()
	listBody, _ := io.ReadAll(respList.Body)
	if respList.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from /api/tickets, got %d: %s", respList.StatusCode, string(listBody))
	}

	var ticketsListResp struct {
		Tickets []struct {
			TicketID         string `json:"ticket_id"`
			CustomerID       string `json:"customer_id"`
			Status           string `json:"status"`
			AssignedReviewer string `json:"assigned_reviewer"`
		} `json:"tickets"`
	}
	if err := json.Unmarshal(listBody, &ticketsListResp); err != nil {
		t.Fatalf("Failed to parse tickets list: %v", err)
	}

	var foundInList bool
	for _, tkt := range ticketsListResp.Tickets {
		if tkt.TicketID == ticketID {
			foundInList = true
			if tkt.Status != "pending" {
				t.Fatalf("ASSERTION FAILED: Console ticket status must be 'pending', got %s", tkt.Status)
			}
			if tkt.AssignedReviewer != "" {
				t.Fatalf("ASSERTION FAILED: Pending console ticket must have empty assigned_reviewer, got %s", tkt.AssignedReviewer)
			}
			break
		}
	}
	if !foundInList {
		t.Fatalf("ASSERTION FAILED: Created ticket %s not found in reviewer console ticket list", ticketID)
	}
	t.Logf("Step 2 PASSED: Reviewer console sees ticket %s as pending and unassigned", ticketID)

	// 4. Customer connects SSE and WebSocket
	custSSE, err := ConnectSSE(ctx, cfg.GatewayURL, custToken)
	if err != nil {
		t.Fatalf("Customer failed to connect SSE stream: %v", err)
	}
	defer custSSE.Close()

	_, err = custSSE.WaitForEvent(5*time.Second, func(e SSEEvent) bool { return e.Event == "connected" })
	if err != nil {
		t.Fatalf("Customer SSE did not receive initial connected handshake: %v", err)
	}

	custWS, err := ConnectWS(ctx, cfg.GatewayURL, custToken)
	if err != nil {
		t.Fatalf("Customer failed to connect WebSocket: %v", err)
	}
	defer custWS.Close()

	ticketChannel := "ticket:" + ticketID
	if err := custWS.Send(map[string]string{
		"action":  "subscribe",
		"channel": ticketChannel,
	}); err != nil {
		t.Fatalf("Customer failed to send subscribe: %v", err)
	}

	_, err = custWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		return m["type"] == "subscribed" && m["channel"] == ticketChannel
	})
	if err != nil {
		t.Fatalf("Customer did not receive ticket channel subscription confirmation: %v", err)
	}
	t.Logf("Step 3 PASSED: Customer connected SSE and WebSocket, subscribed to %s", ticketChannel)

	// 5. Reviewer 1 accepts ticket via Reviewer Console (POST /api/tickets/accept)
	acceptPayload, _ := json.Marshal(map[string]string{
		"ticket_id": ticketID,
	})
	reqAccept, _ := http.NewRequestWithContext(ctx, http.MethodPost, cfg.ConsoleURL+"/api/tickets/accept", bytes.NewReader(acceptPayload))
	reqAccept.Header.Set("Content-Type", "application/json")
	reqAccept.Header.Set("X-Reviewer-Token", rawReviewerToken1)

	respAccept, err := http.DefaultClient.Do(reqAccept)
	if err != nil {
		t.Fatalf("Reviewer 1 failed to send accept request: %v", err)
	}
	defer respAccept.Body.Close()
	acceptBody, _ := io.ReadAll(respAccept.Body)
	if respAccept.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from ticket accept, got %d: %s", respAccept.StatusCode, string(acceptBody))
	}

	var acceptResp struct {
		Message          string `json:"message"`
		CustomerNotified bool   `json:"customer_notified"`
		Ticket           struct {
			TicketID         string `json:"ticket_id"`
			Status           string `json:"status"`
			AssignedReviewer string `json:"assigned_reviewer"`
		} `json:"ticket"`
	}
	if err := json.Unmarshal(acceptBody, &acceptResp); err != nil {
		t.Fatalf("Failed to parse accept response: %v", err)
	}
	if acceptResp.Ticket.Status != "assigned" {
		t.Fatalf("ASSERTION FAILED: Expected ticket status 'assigned', got: %s", acceptResp.Ticket.Status)
	}
	if acceptResp.Ticket.AssignedReviewer != reviewer1ID {
		t.Fatalf("ASSERTION FAILED: Expected assigned_reviewer %s, got: %s", reviewer1ID, acceptResp.Ticket.AssignedReviewer)
	}
	if !acceptResp.CustomerNotified {
		t.Fatalf("ASSERTION FAILED: Expected customer_notified=true in accept response")
	}
	t.Logf("Step 4 PASSED: Reviewer 1 accepted ticket %s (status=assigned, assigned_reviewer=%s)", ticketID, reviewer1ID)

	// 6. CAS Concurrency Race Defense: Reviewer 2 attempts to accept the already-assigned ticket -> 409 Conflict
	reqAcceptConflict, _ := http.NewRequestWithContext(ctx, http.MethodPost, cfg.ConsoleURL+"/api/tickets/accept", bytes.NewReader(acceptPayload))
	reqAcceptConflict.Header.Set("Content-Type", "application/json")
	reqAcceptConflict.Header.Set("X-Reviewer-Token", rawReviewerToken2)

	respConflict, err := http.DefaultClient.Do(reqAcceptConflict)
	if err != nil {
		t.Fatalf("Reviewer 2 failed to send conflicting accept: %v", err)
	}
	defer respConflict.Body.Close()
	if respConflict.StatusCode != http.StatusConflict {
		conflictBody, _ := io.ReadAll(respConflict.Body)
		t.Fatalf("ASSERTION FAILED: Expected 409 Conflict when accepting already-assigned ticket, got %d: %s", respConflict.StatusCode, string(conflictBody))
	}
	t.Logf("Step 5 PASSED: CAS Concurrency Guard verified: second reviewer rejected with 409 Conflict")

	// 7. Dual Delivery Verification on Accept
	// 7a. Live SSE notification: ticket_assigned
	sseAssigned, err := custSSE.WaitForEvent(5*time.Second, func(e SSEEvent) bool {
		return strings.Contains(e.Data, "ticket_assigned") && strings.Contains(e.Data, ticketID)
	})
	if err != nil {
		t.Fatalf("DUAL-DELIVERY FAILURE (SSE): Customer did not receive ticket_assigned SSE event: %v", err)
	}
	t.Logf("Step 6a PASSED [1/2 SSE]: Customer received ticket_assigned event: %s", sseAssigned.Data)

	// 7b. Live WebSocket message: "A support agent has joined your ticket"
	wsJoinMsg, err := custWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		ch, _ := m["channel"].(string)
		content, _ := m["content"].(string)
		return ch == ticketChannel && strings.Contains(content, "has joined your ticket")
	})
	if err != nil {
		t.Fatalf("DUAL-DELIVERY FAILURE (WS): Customer did not receive agent joined message in %s: %v", ticketChannel, err)
	}
	t.Logf("Step 6b PASSED [2/2 WS]: Customer received agent joined message: %+v", wsJoinMsg)

	// 8. Reviewer 1 connects to Reviewer Console WebSocket (/api/chat/ws on :8091)
	revWS, err := ConnectConsoleWS(ctx, cfg.ConsoleURL, rawReviewerToken1)
	if err != nil {
		t.Fatalf("Reviewer 1 failed to connect to Console WebSocket: %v", err)
	}
	defer revWS.Close()

	if err := revWS.Send(map[string]string{
		"action":  "subscribe",
		"channel": ticketChannel,
	}); err != nil {
		t.Fatalf("Reviewer 1 failed to subscribe to %s: %v", ticketChannel, err)
	}

	_, err = revWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		return m["type"] == "subscribed" && m["channel"] == ticketChannel
	})
	if err != nil {
		t.Fatalf("Reviewer 1 did not receive subscription confirmation for %s: %v", ticketChannel, err)
	}
	t.Logf("Step 7 PASSED: Reviewer 1 connected to Console WebSocket and subscribed to %s", ticketChannel)

	// 9. Two-way Real-time Chat
	// 9a. Reviewer 1 sends message to Customer
	reviewerMsgText := "Hello, I am Alice from support. How can I help resolve your delivery incident?"
	if err := revWS.Send(map[string]string{
		"action":  "message",
		"channel": ticketChannel,
		"content": reviewerMsgText,
	}); err != nil {
		t.Fatalf("Reviewer 1 failed to send message: %v", err)
	}

	custReceived, err := custWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		ch, _ := m["channel"].(string)
		content, _ := m["content"].(string)
		sender, _ := m["sender_id"].(string)
		return ch == ticketChannel && content == reviewerMsgText && sender == reviewer1ID
	})
	if err != nil {
		t.Fatalf("Customer failed to receive Reviewer 1 message over WS: %v", err)
	}
	t.Logf("Step 8a PASSED: Customer received Reviewer 1 message over WS: %+v", custReceived)

	// 9b. Customer replies to Reviewer 1
	customerReplyText := "Hi Alice, the package was delivered to the wrong building and water damaged."
	if err := custWS.Send(map[string]string{
		"action":  "message",
		"channel": ticketChannel,
		"content": customerReplyText,
	}); err != nil {
		t.Fatalf("Customer failed to send reply: %v", err)
	}

	revReceived, err := revWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		ch, _ := m["channel"].(string)
		content, _ := m["content"].(string)
		sender, _ := m["sender_id"].(string)
		return ch == ticketChannel && content == customerReplyText && sender == customerID
	})
	if err != nil {
		t.Fatalf("Reviewer 1 failed to receive Customer reply over WS: %v", err)
	}
	t.Logf("Step 8b PASSED: Reviewer 1 received Customer reply over Console WS: %+v", revReceived)

	// 10. Reviewer 1 resolves ticket via Reviewer Console (POST /api/tickets/resolve)
	resolutionNote := "Dispatched replacement courier with priority shipping. Issued full delivery fee credit."
	resolvePayload, _ := json.Marshal(map[string]string{
		"ticket_id":       ticketID,
		"resolution_note": resolutionNote,
	})
	reqResolve, _ := http.NewRequestWithContext(ctx, http.MethodPost, cfg.ConsoleURL+"/api/tickets/resolve", bytes.NewReader(resolvePayload))
	reqResolve.Header.Set("Content-Type", "application/json")
	reqResolve.Header.Set("X-Reviewer-Token", rawReviewerToken1)

	respResolve, err := http.DefaultClient.Do(reqResolve)
	if err != nil {
		t.Fatalf("Reviewer 1 failed to send resolve request: %v", err)
	}
	defer respResolve.Body.Close()
	resolveBody, _ := io.ReadAll(respResolve.Body)
	if respResolve.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from resolve, got %d: %s", respResolve.StatusCode, string(resolveBody))
	}
	t.Logf("Step 9 PASSED: Reviewer 1 resolved ticket %s with 200 OK", ticketID)

	// 11. Dual-Delivery on Resolution
	// 11a. Live SSE notification: ticket_resolved
	sseResolved, err := custSSE.WaitForEvent(5*time.Second, func(e SSEEvent) bool {
		return strings.Contains(e.Data, "ticket_resolved") && strings.Contains(e.Data, ticketID)
	})
	if err != nil {
		t.Fatalf("DUAL-DELIVERY FAILURE (SSE): Customer did not receive ticket_resolved SSE event: %v", err)
	}
	t.Logf("Step 10a PASSED [1/2 SSE]: Customer received ticket_resolved SSE event: %s", sseResolved.Data)

	// 11b. Live WebSocket message: Ticket resolved
	wsResolveMsg, err := custWS.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		ch, _ := m["channel"].(string)
		content, _ := m["content"].(string)
		return ch == ticketChannel && strings.Contains(content, resolutionNote)
	})
	if err != nil {
		t.Fatalf("DUAL-DELIVERY FAILURE (WS): Customer did not receive ticket resolution message: %v", err)
	}
	t.Logf("Step 10b PASSED [2/2 WS]: Customer received ticket resolution system message: %+v", wsResolveMsg)

	// 12. Final status verification in Reviewer Console
	reqFinalList, _ := http.NewRequestWithContext(ctx, http.MethodGet, cfg.ConsoleURL+"/api/tickets", nil)
	reqFinalList.Header.Set("X-Reviewer-Token", rawReviewerToken1)
	respFinalList, err := http.DefaultClient.Do(reqFinalList)
	if err != nil {
		t.Fatalf("Failed to fetch final tickets list: %v", err)
	}
	defer respFinalList.Body.Close()
	finalListBody, _ := io.ReadAll(respFinalList.Body)

	var finalListResp struct {
		Tickets []struct {
			TicketID         string `json:"ticket_id"`
			Status           string `json:"status"`
			AssignedReviewer string `json:"assigned_reviewer"`
			ResolvedBy       string `json:"resolved_by"`
			ResolutionNote   string `json:"resolution_note"`
		} `json:"tickets"`
	}
	if err := json.Unmarshal(finalListBody, &finalListResp); err != nil {
		t.Fatalf("Failed to parse final tickets list: %v", err)
	}

	var finalTicketFound bool
	for _, tkt := range finalListResp.Tickets {
		if tkt.TicketID == ticketID {
			finalTicketFound = true
			if tkt.Status != "resolved" {
				t.Fatalf("ASSERTION FAILED: Final ticket status must be 'resolved', got: %s", tkt.Status)
			}
			if tkt.ResolvedBy != reviewer1ID {
				t.Fatalf("ASSERTION FAILED: ResolvedBy must be %s, got: %s", reviewer1ID, tkt.ResolvedBy)
			}
			if tkt.ResolutionNote != resolutionNote {
				t.Fatalf("ASSERTION FAILED: ResolutionNote mismatch: expected %q, got %q", resolutionNote, tkt.ResolutionNote)
			}
			break
		}
	}
	if !finalTicketFound {
		t.Fatalf("ASSERTION FAILED: Resolved ticket %s not found in console list", ticketID)
	}
	t.Logf("Step 11 PASSED: Verified ticket %s is resolved with correct note and reviewer attribution", ticketID)
	t.Logf("== CUJ-I (Pending-First Support Ticket Lifecycle & Live 2-Way Console Chat) PASSED CLEANLY ==")
}
