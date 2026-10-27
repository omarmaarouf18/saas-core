package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"net/http"
	"strings"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// TestE2E_BEGapsFix covers BE-GAPS-FIX items 1-5 against the live staging
// stack (Caddy -> gateway -> services):
//  1. job lifecycle notifications: job_booked (owner), job_accepted,
//     job_picked_up, job_delivered, job_cancelled (customer) with job_id and
//     event_type on SSE and in history; no job_cancelled when the customer
//     cancels their own job.
//  2. pickup lost race -> 409 job_state_changed; booking fields stay optional.
//  3. photo storage unavailable -> 503 photo_storage_unavailable is covered by
//     unit tests only (staging storage cannot be broken from a test).
//  4. PUT photo_url "" clears the field and deletes the stored object;
//     replacing the photo deletes the old object.
//  5. saved address label required, max 100 runes.
func TestE2E_BEGapsFix(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	ts := time.Now().UnixNano()
	tenantID := fmt.Sprintf("tenant_bgf_%d", ts)
	ownerID := tenantID
	courierID := fmt.Sprintf("cour_bgf_%d", ts)
	custID := fmt.Sprintf("cust_bgf_%d", ts)
	serviceID := fmt.Sprintf("svc_bgf_%d", ts)
	lat, lon := 30.0444, 31.2357

	cleanup := func() {
		db.CleanupTestEntities(ctx, []string{tenantID}, []string{ownerID, courierID, custID})
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
	}
	defer cleanup()
	cleanup()

	if err := db.SeedTenantAndService(ctx, tenantID, ownerID, serviceID, 20.0, 3.0, lat, lon); err != nil {
		t.Fatalf("seed tenant and service: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantID, courierID, courierID+"@staging.local", lat, lon); err != nil {
		t.Fatalf("seed courier: %v", err)
	}
	if err := db.SeedCustomer(ctx, tenantID, custID, custID+"@staging.local"); err != nil {
		t.Fatalf("seed customer: %v", err)
	}

	ownerToken, _ := cfg.GenerateJWT(ownerID, "owner", tenantID, ownerID+"@staging.local")
	courierToken, _ := cfg.GenerateJWT(courierID, "employee", tenantID, courierID+"@staging.local")
	custToken, _ := cfg.GenerateJWT(custID, "user", tenantID, custID+"@staging.local")

	book := func(t *testing.T, extra map[string]any) string {
		t.Helper()
		payload := map[string]any{
			"service_id":     serviceID,
			"user_id":        custToken,
			"payment_method": "cod",
			"location":       map[string]any{"latitude": lat, "longitude": lon},
			"destination":    map[string]any{"latitude": lat, "longitude": lon},
		}
		for k, v := range extra {
			payload[k] = v
		}
		resp, body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/track", custToken, payload)
		if err != nil || resp.StatusCode != http.StatusCreated {
			t.Fatalf("book: %v, %d %s", err, statusOf(resp), string(body))
		}
		var out struct {
			Job struct {
				ID string `json:"id"`
			} `json:"job"`
		}
		_ = json.Unmarshal(body, &out)
		if out.Job.ID == "" {
			t.Fatalf("book: no job id in %s", string(body))
		}
		return out.Job.ID
	}

	// -------------------------------------------------------------------------
	// Item 1: lifecycle notifications carry the stable type, job_id, event_type
	// -------------------------------------------------------------------------
	t.Run("JobLifecycleNotifications", func(t *testing.T) {
		ownerSSE := connectSSEOrFail(t, ctx, cfg.GatewayURL, ownerToken)
		defer ownerSSE.Close()
		custSSE := connectSSEOrFail(t, ctx, cfg.GatewayURL, custToken)
		defer custSSE.Close()

		jobID := book(t, nil)
		waitJobEvent(t, ownerSSE, "job_booked", jobID)

		resp, body, err := PostJSON(ctx, fmt.Sprintf("%s/api/v1/users/employee/jobs/%s/accept", cfg.GatewayURL, jobID), courierToken, nil)
		if err != nil || resp.StatusCode != http.StatusOK {
			t.Fatalf("accept: %v, %d %s", err, statusOf(resp), string(body))
		}
		waitJobEvent(t, custSSE, "job_accepted", jobID)

		resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/pickup", courierToken, map[string]any{"job_id": jobID})
		if err != nil || resp.StatusCode != http.StatusOK {
			t.Fatalf("pickup: %v, %d %s", err, statusOf(resp), string(body))
		}
		waitJobEvent(t, custSSE, "job_picked_up", jobID)

		resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/complete", courierToken, map[string]any{"job_id": jobID, "cash_collected": true})
		if err != nil || resp.StatusCode != http.StatusOK {
			t.Fatalf("complete: %v, %d %s", err, statusOf(resp), string(body))
		}
		waitJobEvent(t, custSSE, "job_delivered", jobID)

		// History carries event_type for the same items.
		got := historyEventTypes(t, ctx, cfg.GatewayURL, custToken, jobID)
		for _, typ := range []string{"job_accepted", "job_picked_up", "job_delivered"} {
			if got[typ] != typ {
				t.Errorf("history for %s: event_type %q, want %q (all: %v)", jobID, got[typ], typ, got)
			}
		}
		if _, ok := got["job_in_transit"]; ok {
			t.Errorf("job_in_transit must not be sent: %v", got)
		}

		// The owner cancels a booked job: the customer is told.
		ownerCancelled := book(t, nil)
		resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/cancel", ownerToken, map[string]any{"job_id": ownerCancelled, "reason": "closing early"})
		if err != nil || resp.StatusCode != http.StatusOK {
			t.Fatalf("owner cancel: %v, %d %s", err, statusOf(resp), string(body))
		}
		waitJobEvent(t, custSSE, "job_cancelled", ownerCancelled)

		// The customer cancels their own job: no job_cancelled back to them.
		// The booking also shows item 2's rule: a recipient with only a
		// phone is still accepted (fields optional, no *_required codes).
		selfCancelled := book(t, map[string]any{"recipient": map[string]any{"phone": "+201012345678"}})
		resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/cancel", custToken, map[string]any{"job_id": selfCancelled, "reason": "changed my mind"})
		if err != nil || resp.StatusCode != http.StatusOK {
			t.Fatalf("customer cancel: %v, %d %s", err, statusOf(resp), string(body))
		}
		time.Sleep(1500 * time.Millisecond)
		if typ, ok := historyEventTypes(t, ctx, cfg.GatewayURL, custToken, selfCancelled)["job_cancelled"]; ok {
			t.Errorf("customer's own cancel produced a notification to them (%q)", typ)
		}
	})

	// -------------------------------------------------------------------------
	// Item 2: lost pickup race answers job_state_changed
	// -------------------------------------------------------------------------
	t.Run("PickupLostRace_JobStateChanged", func(t *testing.T) {
		raceJobID := fmt.Sprintf("job_bgf_race_%d", ts)
		now := time.Now().UTC()
		// Active and assigned, but outside the heading_to_pickup window:
		// the handler's pre-checks pass and the store CAS misses.
		if err := db.SeedJob(ctx, bson.M{
			"_id": raceJobID, "owner_id": ownerID, "user_id": custID, "employee_id": courierID,
			"service_id": serviceID, "status": "active", "payment_method": "cod",
			"location":    bson.M{"latitude": lat, "longitude": lon},
			"destination": bson.M{"latitude": lat, "longitude": lon},
			"created_at":  now, "updated_at": now,
		}); err != nil {
			t.Fatalf("seed race job: %v", err)
		}
		resp, body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/pickup", courierToken, map[string]any{"job_id": raceJobID})
		if err != nil {
			t.Fatalf("pickup: %v", err)
		}
		if resp.StatusCode != http.StatusConflict {
			t.Fatalf("expected 409, got %d: %s", resp.StatusCode, string(body))
		}
		var b map[string]any
		_ = json.Unmarshal(body, &b)
		if b["code"] != "job_state_changed" {
			t.Errorf("expected code job_state_changed, got %s", string(body))
		}
	})

	// -------------------------------------------------------------------------
	// Item 4: removing / replacing the photo deletes the stored object
	// -------------------------------------------------------------------------
	t.Run("ServicePhoto_RemoveAndReplaceDeleteObject", func(t *testing.T) {
		photoURL := fmt.Sprintf("%s/api/v1/users/services/%s/photo", cfg.GatewayURL, serviceID)
		upload := func(format string) string {
			t.Helper()
			img := image.NewRGBA(image.Rect(0, 0, 16, 16))
			for x := 0; x < 16; x++ {
				for y := 0; y < 16; y++ {
					img.Set(x, y, color.RGBA{R: 40, G: 90, B: 200, A: 255})
				}
			}
			var buf bytes.Buffer
			ct := "image/jpeg"
			if format == "png" {
				ct = "image/png"
				_ = png.Encode(&buf, img)
			} else {
				_ = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 85})
			}
			resp, body, err := DoRequestWithHeaders(ctx, http.MethodPost, photoURL,
				map[string]string{"Content-Type": ct, "Authorization": "Bearer " + ownerToken}, buf.Bytes())
			if err != nil || resp.StatusCode != http.StatusOK {
				t.Fatalf("upload %s: %v, %d %s", format, err, statusOf(resp), string(body))
			}
			var out map[string]any
			_ = json.Unmarshal(body, &out)
			key, _ := out["photo_url"].(string)
			if !strings.HasPrefix(key, "services/"+serviceID+"/") {
				t.Fatalf("unexpected key %q", key)
			}
			return key
		}
		readKey := func(key string) int {
			t.Helper()
			resp, _, err := GetJSON(ctx, fmt.Sprintf("%s/api/v1/users/services/photo?key=%s", cfg.GatewayURL, key), custToken)
			if err != nil {
				t.Fatalf("read %s: %v", key, err)
			}
			return resp.StatusCode
		}

		jpgKey := upload("jpeg")
		if code := readKey(jpgKey); code != http.StatusOK {
			t.Fatalf("fresh upload not readable: %d", code)
		}

		// Replace jpg by png: the jpg object is gone.
		pngKey := upload("png")
		if code := readKey(jpgKey); code != http.StatusNotFound {
			t.Errorf("replaced object still readable: %d", code)
		}

		// Remove the way the app does it.
		resp, body, err := PutJSON(ctx, cfg.GatewayURL+"/api/v1/users/services", ownerToken, map[string]any{"id": serviceID, "photo_url": ""})
		if err != nil || resp.StatusCode != http.StatusOK {
			t.Fatalf("PUT photo_url \"\": %v, %d %s", err, statusOf(resp), string(body))
		}
		var updated struct {
			Service struct {
				PhotoURL string `json:"photo_url"`
			} `json:"service"`
		}
		_ = json.Unmarshal(body, &updated)
		if updated.Service.PhotoURL != "" {
			t.Errorf("photo_url not cleared: %q", updated.Service.PhotoURL)
		}
		if code := readKey(pngKey); code != http.StatusNotFound {
			t.Errorf("removed object still readable: %d", code)
		}
		resp, _, err = GetJSON(ctx, photoURL, custToken)
		if err != nil || resp.StatusCode != http.StatusNotFound {
			t.Errorf("service photo after removal: %v, %d (want 404)", err, statusOf(resp))
		}
	})

	// -------------------------------------------------------------------------
	// Item 5: saved address label required, max 100 runes
	// -------------------------------------------------------------------------
	t.Run("SavedAddressLabel_RequiredMax100", func(t *testing.T) {
		authURL := cfg.GatewayURL + "/api/v1/auth/user"
		patch := func(label string) (int, string) {
			t.Helper()
			resp, body, err := PatchJSON(ctx, authURL, custToken, map[string]any{"saved_addresses": []map[string]any{
				{"label": label, "address": "10 Tahrir Square, Cairo", "lat": lat, "lng": lon},
			}})
			if err != nil {
				t.Fatalf("PATCH /auth/user: %v", err)
			}
			return resp.StatusCode, string(body)
		}
		for _, label := range []string{"", "   "} {
			if code, body := patch(label); code != http.StatusBadRequest || !strings.Contains(body, "label is required") {
				t.Errorf("label %q: expected 400 label is required, got %d %s", label, code, body)
			}
		}
		if code, body := patch(strings.Repeat("ب", 101)); code != http.StatusBadRequest {
			t.Errorf("101-rune label: expected 400, got %d %s", code, body)
		}
		if code, body := patch(strings.Repeat("ب", 100)); code != http.StatusOK {
			t.Errorf("100-rune label: expected 200, got %d %s", code, body)
		}
	})
}

func statusOf(resp *http.Response) int {
	if resp == nil {
		return 0
	}
	return resp.StatusCode
}

func connectSSEOrFail(t *testing.T, ctx context.Context, gatewayURL, token string) *SSESubscription {
	t.Helper()
	sub, err := ConnectSSE(ctx, gatewayURL, token)
	if err != nil {
		t.Fatalf("connect SSE: %v", err)
	}
	if _, err := sub.WaitForEvent(5*time.Second, func(e SSEEvent) bool { return e.Event == "connected" }); err != nil {
		sub.Close()
		t.Fatalf("SSE handshake: %v", err)
	}
	return sub
}

// waitJobEvent waits for the notification of type typ about jobID and checks
// it carries event_type == typ.
func waitJobEvent(t *testing.T, sub *SSESubscription, typ, jobID string) {
	t.Helper()
	ev, err := sub.WaitForEvent(10*time.Second, func(e SSEEvent) bool {
		var n map[string]any
		if json.Unmarshal([]byte(e.Data), &n) != nil {
			return false
		}
		return n["type"] == typ && n["job_id"] == jobID
	})
	if err != nil {
		t.Fatalf("no %s SSE event for job %s: %v", typ, jobID, err)
	}
	var n map[string]any
	_ = json.Unmarshal([]byte(ev.Data), &n)
	if n["event_type"] != typ {
		t.Errorf("%s SSE event: event_type %v, want %q (%s)", typ, n["event_type"], typ, ev.Data)
	}
}

// historyEventTypes returns type -> event_type for the caller's history
// items about jobID.
func historyEventTypes(t *testing.T, ctx context.Context, gatewayURL, token, jobID string) map[string]string {
	t.Helper()
	resp, body, err := GetJSON(ctx, gatewayURL+"/api/v1/notifications/history?limit=50", token)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("history: %v, %d %s", err, statusOf(resp), string(body))
	}
	var out struct {
		Notifications []struct {
			Type      string `json:"type"`
			JobID     string `json:"job_id"`
			EventType string `json:"event_type"`
		} `json:"notifications"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatalf("decode history: %v (%s)", err, string(body))
	}
	got := map[string]string{}
	for _, n := range out.Notifications {
		if n.JobID == jobID {
			got[n.Type] = n.EventType
		}
	}
	return got
}
