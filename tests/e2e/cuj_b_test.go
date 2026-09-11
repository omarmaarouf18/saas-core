package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

// TestCUJ_B_KYCSubmissionReviewAndSSEOutcomeDelivery verifies:
//  1. Submission reaches the reviewer console (/api/queue through Caddy reverse proxy).
//  2. Reviewer reject requires mandatory reason (empty and whitespace-only return 400).
//  3. Reviewer approve/reject persists decision and dispatches outcome notification.
//  4. Customer receives the outcome notification live over a real SSE stream through
//     Caddy and the API Gateway (the literal path that failed during the gateway buffering incident).
func TestCUJ_B_KYCSubmissionReviewAndSSEOutcomeDelivery(t *testing.T) {
	cfg := LoadConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	randSuffix := fmt.Sprintf("%d", time.Now().UnixNano()%1000000)
	tenantID := "tenant-cuj-b-" + randSuffix
	customerID := "cust-cuj-b-" + randSuffix
	customer2ID := "cust2-cuj-b-" + randSuffix
	reviewerID := "reviewer-cuj-b-" + randSuffix
	rawReviewerToken := "secret-reviewer-token-" + randSuffix

	defer db.CleanupTestEntities(ctx, []string{tenantID}, []string{customerID, customer2ID, reviewerID})

	// 1. Onboard Reviewer in Staging auth_db.reviewers (hashed at rest per ADR-0021)
	if err := db.SeedReviewer(ctx, reviewerID, "Staging QA Reviewer", rawReviewerToken); err != nil {
		t.Fatalf("Failed to seed reviewer: %v", err)
	}

	// 2. Seed Customer 1 in pending KYC state
	if err := db.SeedKYCSubmission(ctx, customerID, customerID+"@staging.local", "owner", tenantID); err != nil {
		t.Fatalf("Failed to seed KYC submission for customer 1: %v", err)
	}

	// 3. Generate customer JWT and open real SSE stream through Caddy & API Gateway
	custToken, err := cfg.GenerateJWT(customerID, "owner", tenantID, customerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate customer token: %v", err)
	}

	custSSE, err := ConnectSSE(ctx, cfg.GatewayURL, custToken)
	if err != nil {
		t.Fatalf("Customer failed to connect to SSE stream through Caddy: %v", err)
	}
	defer custSSE.Close()

	// Verify initial SSE handshake ("event: connected")
	connEv, err := custSSE.WaitForEvent(5*time.Second, func(e SSEEvent) bool { return e.Event == "connected" })
	if err != nil {
		t.Fatalf("Customer SSE did not receive 'event: connected' handshake through Caddy/Gateway: %v", err)
	}
	t.Logf("Customer SSE connected successfully through proxy chain: %s", connEv.Data)

	// 4. ASSERTION 1: Submission reaches Reviewer Console (GET /api/queue through Caddy reverse proxy)
	queueReq, err := http.NewRequestWithContext(ctx, "GET", cfg.ConsoleURL+"/api/queue", nil)
	if err != nil {
		t.Fatalf("Failed to create queue request: %v", err)
	}
	queueReq.Header.Set("X-Reviewer-Token", rawReviewerToken)

	queueResp, err := http.DefaultClient.Do(queueReq)
	if err != nil {
		t.Fatalf("Reviewer Console GET /api/queue failed: %v", err)
	}
	defer queueResp.Body.Close()

	if queueResp.StatusCode != http.StatusOK {
		qBody, _ := io.ReadAll(queueResp.Body)
		t.Fatalf("Expected 200 OK from reviewer console queue, got %d: %s", queueResp.StatusCode, string(qBody))
	}

	queueBytes, err := io.ReadAll(queueResp.Body)
	if err != nil {
		t.Fatalf("Failed to read queue body: %v", err)
	}

	if !strings.Contains(string(queueBytes), customerID) {
		t.Fatalf("ASSERTION FAILED: Submitted customer %q not found in reviewer console queue: %s", customerID, string(queueBytes))
	}
	t.Logf("Verified: Customer %s present in Reviewer Console pending queue", customerID)

	// 5. ASSERTION 2: Mandatory Rejection Reason check on Reviewer Console (POST /api/review)
	postReview := func(action, reason string) (int, string) {
		bodyMap := map[string]string{
			"user_id": customerID,
			"action":  action,
			"reason":  reason,
		}
		b, _ := json.Marshal(bodyMap)
		req, _ := http.NewRequestWithContext(ctx, "POST", cfg.ConsoleURL+"/api/review", bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Reviewer-Token", rawReviewerToken)

		r, err := http.DefaultClient.Do(req)
		if err != nil {
			return 0, err.Error()
		}
		defer r.Body.Close()
		respB, _ := io.ReadAll(r.Body)
		return r.StatusCode, string(respB)
	}

	// Negative 1: Reject with empty reason -> MUST return 400 Bad Request
	status1, body1 := postReview("reject", "")
	if status1 != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for reject without reason, got %d: %s", status1, body1)
	}
	if !strings.Contains(body1, "reason is required for rejection") {
		t.Errorf("Expected 'reason is required for rejection' in error, got: %s", body1)
	}
	t.Log("Verified: Review rejection without reason rejected with 400 Bad Request")

	// Negative 2: Reject with whitespace-only reason -> MUST return 400 Bad Request
	status2, body2 := postReview("reject", "   \t\n   ")
	if status2 != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for whitespace rejection reason, got %d: %s", status2, body2)
	}
	t.Log("Verified: Whitespace-only rejection reason rejected with 400 Bad Request")

	// 6. Positive Rejection: Reject WITH valid reason
	rejectionReason := "National ID photo is blurry and illegible. Please re-upload a clear scan."
	status3, body3 := postReview("reject", rejectionReason)
	if status3 != http.StatusOK {
		t.Fatalf("Expected 200 OK for valid rejection, got %d: %s", status3, body3)
	}
	t.Log("Verified: Valid rejection recorded with 200 OK by Reviewer Console")

	// 7. ASSERTION 3: Outcome notification reaches customer over the real SSE stream!
	// THIS IS THE EXACT PATH THAT BROKE IN PRODUCTION DUE TO GATEWAY SSE BUFFERING.
	// If api-gateway or Caddy buffers the response, this call times out and fails.
	sseOutcomeEvent, err := custSSE.WaitForEvent(6*time.Second, func(e SSEEvent) bool {
		return strings.Contains(e.Data, "kyc_rejected")
	})
	if err != nil {
		t.Fatalf("GATEWAY BUFFERING / NOTIFICATION FAILURE DETECTED: Customer did not receive kyc_rejected outcome over SSE stream: %v", err)
	}

	t.Logf("Customer received live SSE rejection outcome through Caddy & Gateway: %s", sseOutcomeEvent.Data)

	if !strings.Contains(sseOutcomeEvent.Data, rejectionReason) {
		t.Errorf("Expected SSE notification body to contain rejection reason %q, got: %s", rejectionReason, sseOutcomeEvent.Data)
	}

	// 8. Positive Approval Path (Customer 2)
	if err := db.SeedKYCSubmission(ctx, customer2ID, customer2ID+"@staging.local", "owner", tenantID); err != nil {
		t.Fatalf("Failed to seed KYC submission for customer 2: %v", err)
	}

	cust2Token, err := cfg.GenerateJWT(customer2ID, "owner", tenantID, customer2ID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate customer 2 token: %v", err)
	}

	cust2SSE, err := ConnectSSE(ctx, cfg.GatewayURL, cust2Token)
	if err != nil {
		t.Fatalf("Customer 2 failed to connect to SSE: %v", err)
	}
	defer cust2SSE.Close()

	_, err = cust2SSE.WaitForEvent(5*time.Second, func(e SSEEvent) bool { return e.Event == "connected" })
	if err != nil {
		t.Fatalf("Customer 2 did not receive connected handshake: %v", err)
	}

	// Reviewer approves customer 2 (without needing a reason)
	approveReqBody, _ := json.Marshal(map[string]string{
		"user_id": customer2ID,
		"action":  "approve",
	})
	appReq, _ := http.NewRequestWithContext(ctx, "POST", cfg.ConsoleURL+"/api/review", bytes.NewReader(approveReqBody))
	appReq.Header.Set("Content-Type", "application/json")
	appReq.Header.Set("X-Reviewer-Token", rawReviewerToken)
	appResp, err := http.DefaultClient.Do(appReq)
	if err != nil {
		t.Fatalf("Approve request failed: %v", err)
	}
	defer appResp.Body.Close()

	if appResp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(appResp.Body)
		t.Fatalf("Expected 200 OK for approve, got %d: %s", appResp.StatusCode, string(b))
	}

	// Customer 2 receives kyc_approved event over SSE stream
	approvalEvent, err := cust2SSE.WaitForEvent(6*time.Second, func(e SSEEvent) bool {
		return strings.Contains(e.Data, "kyc_approved")
	})
	if err != nil {
		t.Fatalf("Customer 2 did not receive kyc_approved outcome over SSE: %v", err)
	}

	t.Logf("Customer 2 received live SSE approval outcome through Caddy & Gateway: %s", approvalEvent.Data)
	t.Log("== CUJ-B (Console Queue -> Mandatory Reason Reject -> SSE Outcome Delivery) PASSED CLEANLY ==")
}
