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

// TestContract_ChatService systematically verifies the API contracts, HTTP methods,
// auth requirements, negative validation boundaries, pagination clamping, CAS conflict handling,
// and response schemas for all 8 chat-service routes in the canonical parity inventory.
func TestContract_ChatService(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-contract-chat-%d", rnd)
	customerID := fmt.Sprintf("cust-contract-chat-%d", rnd)
	reviewerID := fmt.Sprintf("rev-contract-chat-%d", rnd)
	rawReviewerToken := fmt.Sprintf("rev-token-chat-%d", rnd)

	_ = FlushReviewerRateLimits(ctx, cfg.RedisURI)
	defer func() {
		_ = FlushReviewerRateLimits(ctx, cfg.RedisURI)
		db.CleanupTestEntities(ctx, []string{tenantID}, []string{customerID})
		_, _ = db.client.Database("staging_auth_db").Collection("reviewers").DeleteOne(ctx, map[string]any{"_id": reviewerID})
	}()

	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}
	if err := db.SeedReviewer(ctx, reviewerID, "Chat Contract Reviewer", rawReviewerToken); err != nil {
		t.Fatalf("Failed to seed reviewer: %v", err)
	}

	custToken, _ := cfg.GenerateJWT(customerID, "user", tenantID, customerID+"@staging.local")
	revHeaders := map[string]string{
		"X-Reviewer-Token": rawReviewerToken,
		"Content-Type":     "application/json",
	}

	// 1. POST /chat/internal/broadcast-location (Internal / Inter-Service)
	// Gateway edge defense: Gateway strips X-Internal-Token from all external ingress,
	// preventing external clients from ever reaching internal-only RPC handlers.
	t.Run("POST_Internal_Broadcast_Location", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/chat/internal/broadcast-location", cfg.GatewayURL)

		// External call without token -> 403 Forbidden
		respNoToken, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, map[string]string{"Content-Type": "application/json"}, []byte("{}"))
		if respNoToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden without internal token, got %d", respNoToken.StatusCode)
		}

		// External call attempting to spoof X-Internal-Token -> Gateway strips header -> 403 Forbidden
		respSpoofToken, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, map[string]string{
			"X-Internal-Token": cfg.InternalToken,
			"Content-Type":     "application/json",
		}, []byte("{}"))
		if respSpoofToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden due to Gateway edge stripping of internal token, got %d", respSpoofToken.StatusCode)
		}

		// Wrong Method -> 405 Method Not Allowed
		respGet, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, nil, nil)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET on internal route, got %d", respGet.StatusCode)
		}
	})

	// Variable to store created ticket ID for subsequent accept/resolve/history tests
	var testTicketID string

	// 2. POST /chat/tickets (Mobile App)
	t.Run("POST_Create_Ticket", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/chat/tickets", cfg.GatewayURL)

		// Negative: Unauthenticated -> 401 Unauthorized
		respUnauth, _, _ := PostJSON(ctx, url, "", map[string]string{"subject": "Lost Order"})
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for unauthenticated ticket creation, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: GET -> 405 Method Not Allowed
		respGet, _, _ := GetJSON(ctx, url, custToken)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET /chat/tickets, got %d", respGet.StatusCode)
		}

		// Negative: Malformed JSON -> 400 Bad Request
		headers := map[string]string{
			"Authorization": "Bearer " + custToken,
			"Content-Type":  "application/json",
		}
		respBadJSON, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, headers, []byte("{bad-json"))
		if respBadJSON.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for malformed JSON, got %d", respBadJSON.StatusCode)
		}

		// Positive: Valid ticket creation -> 201 Created
		ticketBody := map[string]string{
			"subject":     "Contract Test Ticket",
			"description": "Package damaged upon delivery",
		}
		resp, body, err := PostJSON(ctx, url, custToken, ticketBody)
		if err != nil {
			t.Fatalf("Failed to create ticket: %v", err)
		}
		if resp.StatusCode != http.StatusCreated {
			t.Fatalf("Expected 201 Created for ticket creation, got %d. Body: %s", resp.StatusCode, string(body))
		}

		// Response Schema Validation: Verify Dart TicketModel compatibility
		var schema struct {
			TicketID   string `json:"ticket_id"`
			CustomerID string `json:"customer_id"`
			Status     string `json:"status"`
			CreatedAt  string `json:"created_at"`
		}
		if err := json.Unmarshal(body, &schema); err != nil {
			t.Fatalf("Invalid response JSON schema: %v", err)
		}
		if schema.TicketID == "" || schema.Status != "pending" {
			t.Errorf("Ticket schema mismatch: ticket_id=%q status=%q", schema.TicketID, schema.Status)
		}
		testTicketID = schema.TicketID
	})

	// 3. GET /chat/tickets/mine (Mobile App)
	t.Run("GET_Customer_Tickets_Mine", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/chat/tickets/mine", cfg.GatewayURL)

		// Negative: Unauthenticated -> 401 Unauthorized
		respUnauth, _, _ := GetJSON(ctx, url, "")
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for unauthenticated tickets/mine, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: POST -> 405 Method Not Allowed
		respPost, _, _ := PostJSON(ctx, url, custToken, nil)
		if respPost.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for POST /chat/tickets/mine, got %d", respPost.StatusCode)
		}

		// Pagination Boundary Test: page=0, negative page, limit>max, limit=0
		paginationCases := []struct {
			query         string
			expectedPage  int
			expectedLimit int
		}{
			{"?page=0&limit=0", 1, 20},
			{"?page=-5&limit=500", 1, 20},
			{"?page=1&limit=10", 1, 10},
		}

		for _, pc := range paginationCases {
			resp, body, err := GetJSON(ctx, url+pc.query, custToken)
			if err != nil {
				t.Fatalf("Request with %s failed: %v", pc.query, err)
			}
			if resp.StatusCode != http.StatusOK {
				t.Fatalf("Expected 200 OK for pagination query %s, got %d", pc.query, resp.StatusCode)
			}
			var pResp struct {
				Tickets []any `json:"tickets"`
				Total   int   `json:"total"`
				Page    int   `json:"page"`
				Limit   int   `json:"limit"`
			}
			if err := json.Unmarshal(body, &pResp); err != nil {
				t.Fatalf("Failed to parse pagination response: %v", err)
			}
			if pResp.Page != pc.expectedPage || pResp.Limit != pc.expectedLimit {
				t.Errorf("Pagination clamping failed for %s: expected page=%d limit=%d, got page=%d limit=%d",
					pc.query, pc.expectedPage, pc.expectedLimit, pResp.Page, pResp.Limit)
			}
		}
	})

	// 4. GET /admin/tickets (Ops Console)
	t.Run("GET_Admin_Tickets", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/tickets", cfg.ConsoleURL)

		// Negative: Missing reviewer token -> 401 Unauthorized
		respUnauth, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, nil, nil)
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 without reviewer token, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: POST -> 405 Method Not Allowed
		respPost, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, revHeaders, []byte("{}"))
		if respPost.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for POST /admin/tickets, got %d", respPost.StatusCode)
		}

		// Positive & Pagination Test:
		clampURL := fmt.Sprintf("%s?page=-2&limit=999", url)
		resp, body, err := DoRequestWithHeaders(ctx, http.MethodGet, clampURL, revHeaders, nil)
		if err != nil {
			t.Fatalf("GET /api/tickets failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for reviewer tickets list, got %d. Body: %s", resp.StatusCode, string(body))
		}
		var listSchema struct {
			Tickets []map[string]any `json:"tickets"`
			Total   int              `json:"total"`
			Page    int              `json:"page"`
			Limit   int              `json:"limit"`
		}
		if err := json.Unmarshal(body, &listSchema); err != nil {
			t.Fatalf("Invalid response JSON schema: %v", err)
		}
		if listSchema.Page != 1 || listSchema.Limit != 20 {
			t.Errorf("Expected clamped page=1 limit=20, got page=%d limit=%d", listSchema.Page, listSchema.Limit)
		}
	})

	// 5. POST /admin/tickets/accept (Ops Console)
	t.Run("POST_Admin_Accept_Ticket", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/tickets/accept", cfg.ConsoleURL)

		// Negative: Missing reviewer token -> 401 Unauthorized
		respUnauth, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, nil, []byte(fmt.Sprintf(`{"ticket_id":"%s"}`, testTicketID)))
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 without reviewer token, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: GET -> 405 Method Not Allowed
		respGet, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, revHeaders, nil)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET /api/tickets/accept, got %d", respGet.StatusCode)
		}

		// Negative: Missing ticket_id -> 400 Bad Request
		respNoID, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, revHeaders, []byte("{}"))
		if respNoID.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for missing ticket_id, got %d", respNoID.StatusCode)
		}

		// Negative: Non-existent ticket_id -> 404 Not Found
		respNotFound, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, revHeaders, []byte(`{"ticket_id":"tkt-nonexistent-00000000"}`))
		if respNotFound.StatusCode != http.StatusNotFound {
			t.Errorf("Expected 404 for non-existent ticket, got %d", respNotFound.StatusCode)
		}

		// Positive: Accept pending ticket -> 200 OK
		acceptPayload := []byte(fmt.Sprintf(`{"ticket_id":"%s"}`, testTicketID))
		resp, body, err := DoRequestWithHeaders(ctx, http.MethodPost, url, revHeaders, acceptPayload)
		if err != nil {
			t.Fatalf("POST /api/tickets/accept failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK on accept, got %d. Body: %s", resp.StatusCode, string(body))
		}

		// Response Schema Validation: Verify nested ticket structure
		var acceptSchema struct {
			Message          string `json:"message"`
			CustomerNotified bool   `json:"customer_notified"`
			Ticket           struct {
				ID               string `json:"id"`
				Status           string `json:"status"`
				AssignedReviewer string `json:"assigned_reviewer"`
			} `json:"ticket"`
		}
		if err := json.Unmarshal(body, &acceptSchema); err != nil {
			t.Fatalf("Invalid response JSON: %v", err)
		}
		if acceptSchema.Ticket.Status != "assigned" || acceptSchema.Ticket.AssignedReviewer != reviewerID {
			t.Errorf("Expected status='assigned' assigned_reviewer=%q, got status=%q reviewer=%q",
				reviewerID, acceptSchema.Ticket.Status, acceptSchema.Ticket.AssignedReviewer)
		}

		// CAS Conflict Concurrency Guard: Double-accept on already assigned ticket -> 409 Conflict
		respConflict, bodyConflict, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, revHeaders, acceptPayload)
		if respConflict.StatusCode != http.StatusConflict {
			t.Fatalf("Expected 409 Conflict for double-accept, got %d. Body: %s", respConflict.StatusCode, string(bodyConflict))
		}
		var conflictErr struct {
			Error string `json:"error"`
		}
		if err := json.Unmarshal(bodyConflict, &conflictErr); err != nil || conflictErr.Error == "" {
			t.Errorf("Expected structured error in 409 response, got: %s", string(bodyConflict))
		}
	})

	// 6. POST /admin/tickets/resolve (Ops Console)
	t.Run("POST_Admin_Resolve_Ticket", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/tickets/resolve", cfg.ConsoleURL)

		// Negative: Missing reviewer token (with resolution note present) -> 401 Unauthorized
		resolveBodyWithNote := []byte(fmt.Sprintf(`{"ticket_id":"%s","resolution_note":"Resolved by contract test"}`, testTicketID))
		respUnauth, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, map[string]string{"Content-Type": "application/json"}, resolveBodyWithNote)
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 without reviewer token, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: GET -> 405 Method Not Allowed
		respGet, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, revHeaders, nil)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET /api/tickets/resolve, got %d", respGet.StatusCode)
		}

		// Negative: Missing resolution note -> 400 Bad Request
		respNoNote, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, revHeaders, []byte(fmt.Sprintf(`{"ticket_id":"%s"}`, testTicketID)))
		if respNoNote.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing resolution note, got %d", respNoNote.StatusCode)
		}

		// Positive: Resolve ticket -> 200 OK
		resp, body, err := DoRequestWithHeaders(ctx, http.MethodPost, url, revHeaders, resolveBodyWithNote)
		if err != nil {
			t.Fatalf("POST /api/tickets/resolve failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK on resolve, got %d. Body: %s", resp.StatusCode, string(body))
		}

		// CAS Conflict Concurrency Guard: Double-resolve on already resolved ticket -> 409 Conflict
		respDoubleResolve, bodyDoubleResolve, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, revHeaders, resolveBodyWithNote)
		if respDoubleResolve.StatusCode != http.StatusConflict {
			t.Fatalf("Expected 409 Conflict for double-resolve, got %d. Body: %s", respDoubleResolve.StatusCode, string(bodyDoubleResolve))
		}
	})

	// 7. GET /chat/history (Mobile App / Console)
	t.Run("GET_Chat_History", func(t *testing.T) {
		channel := fmt.Sprintf("ticket:%s", testTicketID)
		url := fmt.Sprintf("%s/api/v1/chat/history?channel=%s", cfg.GatewayURL, channel)

		// Negative: Unauthenticated / Missing token -> 400 Bad Request (requester_id required)
		respNoToken, _, _ := GetJSON(ctx, url, "")
		if respNoToken.StatusCode != http.StatusBadRequest && respNoToken.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 400/401 for unauthenticated history, got %d", respNoToken.StatusCode)
		}

		// Negative: Invalid / forged token -> 403 Forbidden
		respForged, _, _ := GetJSON(ctx, url, "forged.token.here")
		if respForged.StatusCode != http.StatusForbidden && respForged.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 403/401 for forged token on chat history, got %d", respForged.StatusCode)
		}

		// Negative: Missing channel param -> 400 Bad Request
		urlNoChannel := fmt.Sprintf("%s/api/v1/chat/history", cfg.GatewayURL)
		respNoChan, _, _ := GetJSON(ctx, urlNoChannel, custToken)
		if respNoChan.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for history request missing channel param, got %d", respNoChan.StatusCode)
		}

		// Negative: Wrong Method: POST -> 405 Method Not Allowed
		respPost, _, _ := PostJSON(ctx, url, custToken, nil)
		if respPost.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for POST /chat/history, got %d", respPost.StatusCode)
		}

		// Positive: Customer fetches ticket chat history -> 200 OK with message slice
		resp, body, err := GetJSON(ctx, url, custToken)
		if err != nil {
			t.Fatalf("GET /chat/history failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for chat history, got %d. Body: %s", resp.StatusCode, string(body))
		}
		var historyMessages []map[string]any
		if err := json.Unmarshal(body, &historyMessages); err != nil {
			t.Fatalf("Invalid response JSON array for chat history: %v", err)
		}
	})

	// 8. GET /chat/ws (Mobile App / Console)
	t.Run("GET_Chat_WebSocket", func(t *testing.T) {
		// Negative: Connect without token -> Dial fails with 401 Unauthorized
		_, errUnauth := ConnectWS(ctx, cfg.GatewayURL, "")
		if errUnauth == nil {
			t.Errorf("Expected WebSocket dial failure without token")
		}

		// Negative: Connect with invalid token -> 401 Unauthorized
		_, errBadToken := ConnectWS(ctx, cfg.GatewayURL, "invalid-token-signature")
		if errBadToken == nil {
			t.Errorf("Expected WebSocket dial failure with invalid token")
		}

		// Positive: Connect with valid customer token -> successful upgrade
		ws, err := ConnectWS(ctx, cfg.GatewayURL, custToken)
		if err != nil {
			t.Fatalf("Failed to establish WebSocket with valid token: %v", err)
		}
		defer ws.Close()
	})
}
