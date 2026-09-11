package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

// TestCUJ_A_CascadeOfferAcceptAndLiveTracking verifies:
//  1. Customer books -> cascade creates job in pending_dispatch and offers to nearest courier.
//  2. Only the correct courier receives the offer notification via real SSE (N-01/N-02 isolation).
//  3. Price remains deferred/null until acceptance, correctly locked afterward.
//  4. Live tracking survives courier app navigation (F-01/F-02).
//  5. Customer WebSocket map feed reflects real position updates through Caddy & API Gateway.
func TestCUJ_A_CascadeOfferAcceptAndLiveTracking(t *testing.T) {
	cfg := LoadConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	randSuffix := fmt.Sprintf("%d", time.Now().UnixNano()%1000000)
	tenantID := "tenant-cuj-a-" + randSuffix
	ownerID := tenantID // in Quick Delivery architecture, owner user ID is tenant ID
	serviceID := "svc-cuj-a-" + randSuffix
	customerID := "cust-cuj-a-" + randSuffix
	courier1ID := "courier1-near-" + randSuffix
	courier2ID := "courier2-far-" + randSuffix

	defer db.CleanupTestEntities(ctx, []string{tenantID}, []string{ownerID, customerID, courier1ID, courier2ID})

	// 1. Seed Tenant, Paid Subscription, and Service in Staging DB
	// Service base price = 25.0 EGP, 3.0 EGP/km, located at Downtown Cairo (30.0444, 31.2357)
	serviceLat := 30.0444
	serviceLon := 31.2357
	if err := db.SeedTenantAndService(ctx, tenantID, ownerID, serviceID, 25.0, 3.0, serviceLat, serviceLon); err != nil {
		t.Fatalf("Failed to seed tenant and service: %v", err)
	}
	if err := db.SeedWallet(ctx, tenantID, 1000.0); err != nil {
		t.Fatalf("Failed to seed tenant wallet: %v", err)
	}

	// 2. Seed Couriers in Staging DB:
	// Courier 1: ~100m from service (30.0450, 31.2360) -> Nearest candidate
	if err := db.SeedCourier(ctx, tenantID, courier1ID, courier1ID+"@staging.local", 30.0450, 31.2360); err != nil {
		t.Fatalf("Failed to seed courier 1: %v", err)
	}
	// Courier 2: ~8km from service (30.0900, 31.3000) -> Far candidate
	if err := db.SeedCourier(ctx, tenantID, courier2ID, courier2ID+"@staging.local", 30.0900, 31.3000); err != nil {
		t.Fatalf("Failed to seed courier 2: %v", err)
	}

	// Customer record in auth_db (required by chat-service WebSocket auth check)
	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}

	// 3. Generate signed JWTs for all actors
	custToken, err := cfg.GenerateJWT(customerID, "user", tenantID, customerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate customer token: %v", err)
	}
	courier1Token, err := cfg.GenerateJWT(courier1ID, "employee", tenantID, courier1ID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate courier 1 token: %v", err)
	}
	courier2Token, err := cfg.GenerateJWT(courier2ID, "employee", tenantID, courier2ID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate courier 2 token: %v", err)
	}

	// 4. Open real SSE stream connections for both couriers through Caddy & API Gateway
	courier1SSE, err := ConnectSSE(ctx, cfg.GatewayURL, courier1Token)
	if err != nil {
		t.Fatalf("Courier 1 failed to open SSE stream through gateway: %v", err)
	}
	defer courier1SSE.Close()

	courier2SSE, err := ConnectSSE(ctx, cfg.GatewayURL, courier2Token)
	if err != nil {
		t.Fatalf("Courier 2 failed to open SSE stream through gateway: %v", err)
	}
	defer courier2SSE.Close()

	// Verify both couriers received initial SSE "connected" event
	ev1, err := courier1SSE.WaitForEvent(5*time.Second, func(e SSEEvent) bool { return e.Event == "connected" })
	if err != nil {
		t.Fatalf("Courier 1 did not receive SSE connected handshake: %v", err)
	}
	t.Logf("Courier 1 SSE connected verified: %s", ev1.Data)

	ev2, err := courier2SSE.WaitForEvent(5*time.Second, func(e SSEEvent) bool { return e.Event == "connected" })
	if err != nil {
		t.Fatalf("Courier 2 did not receive SSE connected handshake: %v", err)
	}
	t.Logf("Courier 2 SSE connected verified: %s", ev2.Data)

	// 5. Customer books a delivery job (POST /api/v1/users/jobs/track)
	bookPayload := map[string]any{
		"service_id":     serviceID,
		"user_id":        custToken,
		"payment_method": "wallet",
		"location": map[string]float64{
			"latitude":  serviceLat,
			"longitude": serviceLon,
		},
	}

	resp, respBody, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/track", custToken, bookPayload)
	if err != nil {
		t.Fatalf("POST /api/v1/users/jobs/track failed: %v", err)
	}
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("Expected 201 Created from TrackJob, got %d: %s", resp.StatusCode, string(respBody))
	}

	var trackResp struct {
		Job struct {
			ID                       string     `json:"id"`
			Status                   string     `json:"status"`
			EmployeeID               string     `json:"employee_id"`
			CurrentOfferedEmployeeID string     `json:"current_offered_employee_id"`
			BookedDistance           float64    `json:"booked_distance"`
			SuggestedPrice           float64    `json:"suggested_price"`
			LockedEscrowAmount       float64    `json:"locked_escrow_amount"`
			OfferExpiresAt           *time.Time `json:"offer_expires_at"`
		} `json:"job"`
	}
	if err := json.Unmarshal(respBody, &trackResp); err != nil {
		t.Fatalf("Failed to parse TrackJob response: %v", err)
	}

	jobID := trackResp.Job.ID
	if jobID == "" {
		t.Fatalf("Expected non-empty job ID in TrackJob response")
	}

	// ASSERTION 1: Job created in pending_dispatch and offered strictly to nearest Courier 1
	if trackResp.Job.Status != "pending_dispatch" {
		t.Errorf("Expected initial status 'pending_dispatch', got %q", trackResp.Job.Status)
	}
	if trackResp.Job.CurrentOfferedEmployeeID != courier1ID {
		t.Errorf("Expected offer to nearest courier %q, got %q", courier1ID, trackResp.Job.CurrentOfferedEmployeeID)
	}

	// ASSERTION 2: Price is null/deferred until acceptance
	if trackResp.Job.BookedDistance != 0 {
		t.Errorf("Expected BookedDistance == 0 before acceptance, got %v", trackResp.Job.BookedDistance)
	}
	if trackResp.Job.SuggestedPrice != 0 {
		t.Errorf("Expected SuggestedPrice == 0 before acceptance, got %v", trackResp.Job.SuggestedPrice)
	}
	if trackResp.Job.LockedEscrowAmount != 0 {
		t.Errorf("Expected LockedEscrowAmount == 0 before acceptance, got %v", trackResp.Job.LockedEscrowAmount)
	}

	// 6. ASSERTION 3: Offer Notification Isolation (N-01/N-02)
	// Courier 1 must receive the offer notification via real SSE
	offerEvent, err := courier1SSE.WaitForEvent(6*time.Second, func(e SSEEvent) bool {
		return strings.Contains(e.Data, "job_offer") || strings.Contains(e.Data, jobID)
	})
	if err != nil {
		t.Fatalf("Courier 1 failed to receive job_offer notification over SSE: %v", err)
	}
	t.Logf("Courier 1 received job offer over SSE: %s", offerEvent.Data)

	// Courier 2 must NOT receive the offer notification (assert timeout)
	noOfferEvent, err := courier2SSE.WaitForEvent(2*time.Second, func(e SSEEvent) bool {
		return strings.Contains(e.Data, jobID)
	})
	if err == nil && noOfferEvent != nil {
		t.Fatalf("LEAK DETECTED (N-01): Courier 2 received offer notification meant for Courier 1: %s", noOfferEvent.Data)
	}
	t.Log("Verified: Courier 2 did NOT receive leaked SSE offer event")

	// Courier 2 notification history query must also have ZERO leaked alerts (N-02 check)
	_, notifBody, err := GetJSON(ctx, cfg.GatewayURL+"/api/v1/notifications", courier2Token)
	if err != nil {
		t.Fatalf("Courier 2 failed to fetch notifications: %v", err)
	}
	if strings.Contains(string(notifBody), jobID) {
		t.Fatalf("LEAK DETECTED (N-02): Courier 2 notification history disclosed private job offer %s", jobID)
	}
	t.Log("Verified: Courier 2 notification history contains 0 leaked job alerts")

	// 7. Courier 1 accepts the offer (POST /api/v1/users/employee/jobs/accept)
	acceptPayload := map[string]string{
		"job_id": jobID,
	}
	acceptResp, acceptBody, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/employee/jobs/accept", courier1Token, acceptPayload)
	if err != nil {
		t.Fatalf("POST /api/v1/users/employee/jobs/accept failed: %v", err)
	}
	if acceptResp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from AcceptJobOffer, got %d: %s", acceptResp.StatusCode, string(acceptBody))
	}

	// 8. ASSERTION 4: Price is calculated and locked upon acceptance
	_, getJobBody, err := GetJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/get?id="+jobID, custToken)
	if err != nil {
		t.Fatalf("Failed to fetch accepted job: %v", err)
	}

	var acceptedJob struct {
		ID                 string  `json:"id"`
		Status             string  `json:"status"`
		EmployeeID         string  `json:"employee_id"`
		BookedDistance     float64 `json:"booked_distance"`
		LockedEscrowAmount float64 `json:"locked_escrow_amount"`
	}
	if err := json.Unmarshal(getJobBody, &acceptedJob); err != nil {
		t.Fatalf("Failed to parse get job response: %v", err)
	}

	if acceptedJob.Status != "active" {
		t.Errorf("Expected job status 'active' after accept, got %q", acceptedJob.Status)
	}
	if acceptedJob.EmployeeID != courier1ID {
		t.Errorf("Expected employee_id to be %q, got %q", courier1ID, acceptedJob.EmployeeID)
	}
	if acceptedJob.BookedDistance <= 0 {
		t.Errorf("Expected BookedDistance > 0 after acceptance, got %v", acceptedJob.BookedDistance)
	}
	if acceptedJob.LockedEscrowAmount <= 0 {
		t.Errorf("Expected LockedEscrowAmount > 0 after acceptance, got %v", acceptedJob.LockedEscrowAmount)
	}
	t.Logf("Verified: Price locked post-acceptance: Distance=%.3f km, Locked Escrow=%.2f EGP", acceptedJob.BookedDistance, acceptedJob.LockedEscrowAmount)

	// 9. Customer connects to Live WebSocket Feed (chat-service channel job:<jobID>)
	wsClient, err := ConnectWS(ctx, cfg.GatewayURL, custToken)
	if err != nil {
		t.Fatalf("Customer failed to connect to WebSocket: %v", err)
	}
	defer wsClient.Close()

	// Customer subscribes to job tracking channel
	joinMsg := map[string]any{
		"action":  "subscribe",
		"channel": "job:" + jobID,
	}
	if err := wsClient.Send(joinMsg); err != nil {
		t.Fatalf("Customer failed to send subscribe message: %v", err)
	}

	subConfirm, err := wsClient.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		msgType, _ := m["type"].(string)
		return msgType == "subscribed"
	})
	if err != nil {
		t.Fatalf("Customer failed to receive subscribed confirmation: %v", err)
	}
	t.Logf("Customer subscribed to job channel verified: %+v", subConfirm)

	// 10. ASSERTION 5: Live tracking survives courier navigating within the app (F-01)
	// Courier performs multiple unrelated app queries (profile, jobs history, notifications)
	_, _, _ = GetJSON(ctx, cfg.GatewayURL+"/api/v1/auth/profile", courier1Token)
	_, _, _ = GetJSON(ctx, cfg.GatewayURL+"/api/v1/notifications", courier1Token)
	_, _, _ = GetJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/get?id="+jobID, courier1Token)

	// Courier emits live GPS location update 1 (arrived at pickup location)
	loc1Lat := serviceLat
	loc1Lon := serviceLon
	loc1Payload := map[string]any{
		"job_id":          jobID,
		"requester_token": courier1Token,
		"latitude":        loc1Lat,
		"longitude":       loc1Lon,
	}
	loc1Resp, loc1Body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/location/update", courier1Token, loc1Payload)
	if err != nil {
		t.Fatalf("UpdateJobLocation 1 failed: %v", err)
	}
	if loc1Resp.StatusCode != http.StatusOK {
		t.Fatalf("UpdateJobLocation 1 expected 200 OK, got %d: %s", loc1Resp.StatusCode, string(loc1Body))
	}

	// ASSERTION 6: Customer WebSocket receives real-time position update 1
	wsMsg1, err := wsClient.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		msgType, _ := m["type"].(string)
		return msgType == "location_update"
	})
	if err != nil {
		t.Fatalf("Customer WebSocket failed to receive location_update 1: %v", err)
	}

	t.Logf("Customer received WebSocket location_update 1: %+v", wsMsg1)
	if latVal, ok := wsMsg1["latitude"].(float64); !ok || fmt.Sprintf("%.4f", latVal) != fmt.Sprintf("%.4f", loc1Lat) {
		t.Errorf("Expected latitude %.4f in WebSocket update 1, got %v", loc1Lat, wsMsg1["latitude"])
	}

	// Wait 3.5 seconds to satisfy the 3-second minimum throttle window between location updates
	time.Sleep(3500 * time.Millisecond)
	loc2Lat := serviceLat + 0.0001
	loc2Lon := serviceLon + 0.0001
	loc2Payload := map[string]any{
		"job_id":          jobID,
		"requester_token": courier1Token,
		"latitude":        loc2Lat,
		"longitude":       loc2Lon,
	}
	loc2Resp, loc2Body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/location/update", courier1Token, loc2Payload)
	if err != nil {
		t.Fatalf("UpdateJobLocation 2 failed: %v", err)
	}
	if loc2Resp.StatusCode != http.StatusOK {
		t.Fatalf("UpdateJobLocation 2 expected 200 OK, got %d: %s", loc2Resp.StatusCode, string(loc2Body))
	}

	wsMsg2, err := wsClient.WaitForMessage(5*time.Second, func(m map[string]any) bool {
		msgType, _ := m["type"].(string)
		return msgType == "location_update"
	})
	if err != nil {
		t.Fatalf("Customer WebSocket failed to receive location_update 2: %v", err)
	}

	t.Logf("Customer received WebSocket location_update 2: %+v", wsMsg2)
	if latVal, ok := wsMsg2["latitude"].(float64); !ok || fmt.Sprintf("%.4f", latVal) != fmt.Sprintf("%.4f", loc2Lat) {
		t.Errorf("Expected latitude %.4f in WebSocket update 2, got %v", loc2Lat, wsMsg2["latitude"])
	}

	t.Log("== CUJ-A (Cascade Offer -> Accept -> Pricing Lock -> Live Map Tracking) PASSED CLEANLY ==")
}
