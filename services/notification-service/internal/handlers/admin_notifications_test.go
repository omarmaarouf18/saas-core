package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/notification-service/internal/store"
	"github.com/project/notification-service/internal/templates"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
)

func setupAdminNotificationTestContext(t *testing.T) (*Notification, *memoryStore, *http.ServeMux, string, *httptest.Server) {
	t.Helper()
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	validReviewerToken := "valid-reviewer-token-xyz"
	internalToken := "test-internal-token-456"

	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		if r.Header.Get("X-Internal-Token") != internalToken {
			w.WriteHeader(http.StatusUnauthorized)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "unauthorized internal token"})
			return
		}

		if r.URL.Path == "/auth/reviewer/verify" {
			revTok := r.Header.Get("X-Reviewer-Token")
			if revTok == validReviewerToken {
				w.WriteHeader(http.StatusOK)
				_ = json.NewEncoder(w).Encode(map[string]string{
					"id":   "rev-operator-1",
					"name": "Operator Sarah",
				})
				return
			}
			w.WriteHeader(http.StatusUnauthorized)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid reviewer token"})
			return
		}

		if r.URL.Path == "/auth/internal/audience-lookup" {
			var req map[string]any
			_ = json.NewDecoder(r.Body).Decode(&req)
			kind, _ := req["kind"].(string)

			switch kind {
			case "user":
				uid, _ := req["user_id"].(string)
				if uid == "" {
					uid = "resolved-user-1"
				}
				w.WriteHeader(http.StatusOK)
				_ = json.NewEncoder(w).Encode(map[string]any{
					"user_ids": []string{uid},
					"total":    1,
					"page":     1,
					"limit":    500,
				})
			case "role":
				w.WriteHeader(http.StatusOK)
				_ = json.NewEncoder(w).Encode(map[string]any{
					"user_ids": []string{"cust-1", "cust-2", "cust-3"},
					"total":    3,
					"page":     1,
					"limit":    500,
				})
			case "tenant":
				w.WriteHeader(http.StatusOK)
				_ = json.NewEncoder(w).Encode(map[string]any{
					"user_ids": []string{"owner-alpha", "courier-alpha-1"},
					"total":    2,
					"page":     1,
					"limit":    500,
				})
			case "everyone":
				// Return 1,200 users total to trigger confirmation check
				w.WriteHeader(http.StatusOK)
				_ = json.NewEncoder(w).Encode(map[string]any{
					"user_ids": []string{"user-1", "user-2"},
					"total":    1200,
					"page":     1,
					"limit":    500,
				})
			default:
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "unknown kind"})
			}
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	t.Cleanup(mr.Close)

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })

	memStore := newMemoryStore()
	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       mockAuth.URL,
		InternalServiceToken: internalToken,
		AllowedOrigin:        "*",
	}

	n := NewNotification(sseHub, memStore, cfg, rdb)
	mux := http.NewServeMux()
	n.RegisterRoutes(mux)

	return n, memStore, mux, validReviewerToken, mockAuth
}

func TestAdminNotifications_LifecycleAndSafety(t *testing.T) {
	_, _, mux, validRevToken, mockAuth := setupAdminNotificationTestContext(t)
	defer mockAuth.Close()

	sendEndpoint := "/admin/notifications/send"

	makeRequest := func(method, path string, body any, internalTok, revTok string) *httptest.ResponseRecorder {
		var req *http.Request
		if body != nil {
			b, _ := json.Marshal(body)
			req = httptest.NewRequest(method, path, bytes.NewReader(b))
		} else {
			req = httptest.NewRequest(method, path, nil)
		}
		if internalTok != "" {
			req.Header.Set("X-Internal-Token", internalTok)
		}
		if revTok != "" {
			req.Header.Set("X-Reviewer-Token", revTok)
		}
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec
	}

	// 1. Auth Failures
	t.Run("Auth failures", func(t *testing.T) {
		validPayload := map[string]any{
			"reason":   "Routine ops maintenance alert",
			"audience": map[string]any{"kind": "role", "role": "customers"},
			"title":    map[string]string{"en": "Maintenance", "ar": "صيانة"},
			"body":     map[string]string{"en": "Scheduled outage tonight", "ar": "انقطاع مجدول الليلة"},
		}

		// Missing internal token
		rec := makeRequest(http.MethodPost, sendEndpoint, validPayload, "", validRevToken)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 for missing internal token, got %d", rec.Code)
		}

		// Missing reviewer token
		rec = makeRequest(http.MethodPost, sendEndpoint, validPayload, "test-internal-token-456", "")
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 for missing reviewer token, got %d", rec.Code)
		}

		// Invalid reviewer token
		rec = makeRequest(http.MethodPost, sendEndpoint, validPayload, "test-internal-token-456", "wrong-secret")
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 for invalid reviewer token, got %d", rec.Code)
		}
	})

	// 2. Reason Validation (1-1000 chars)
	t.Run("Reason validation", func(t *testing.T) {
		payloadNoReason := map[string]any{
			"reason":   "",
			"audience": map[string]any{"kind": "role", "role": "customers"},
			"title":    map[string]string{"en": "Maintenance", "ar": "صيانة"},
			"body":     map[string]string{"en": "Tonight", "ar": "الليلة"},
		}
		rec := makeRequest(http.MethodPost, sendEndpoint, payloadNoReason, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "invalid_reason") {
			t.Errorf("expected 400 invalid_reason, got %d: %s", rec.Code, rec.Body.String())
		}

		payloadLongReason := map[string]any{
			"reason":   strings.Repeat("a", 1001),
			"audience": map[string]any{"kind": "role", "role": "customers"},
			"title":    map[string]string{"en": "Maintenance", "ar": "صيانة"},
			"body":     map[string]string{"en": "Tonight", "ar": "الليلة"},
		}
		rec = makeRequest(http.MethodPost, sendEndpoint, payloadLongReason, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "invalid_reason") {
			t.Errorf("expected 400 invalid_reason for >1000 chars, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 3. Bilingual Title & Body Validation
	t.Run("Bilingual title and body validation", func(t *testing.T) {
		// Missing Arabic title
		missingAR := map[string]any{
			"reason":   "Valid ops reason",
			"audience": map[string]any{"kind": "role", "role": "customers"},
			"title":    map[string]string{"en": "Maintenance"},
			"body":     map[string]string{"en": "Outage tonight", "ar": "صيانة"},
		}
		rec := makeRequest(http.MethodPost, sendEndpoint, missingAR, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "invalid_title") {
			t.Errorf("expected 400 invalid_title, got %d: %s", rec.Code, rec.Body.String())
		}

		// Missing English body
		missingENBody := map[string]any{
			"reason":   "Valid ops reason",
			"audience": map[string]any{"kind": "role", "role": "customers"},
			"title":    map[string]string{"en": "Maintenance", "ar": "صيانة"},
			"body":     map[string]string{"ar": "صيانة الليلة"},
		}
		rec = makeRequest(http.MethodPost, sendEndpoint, missingENBody, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "invalid_body") {
			t.Errorf("expected 400 invalid_body, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 4. Deep Link Hygiene
	t.Run("Deep link validation", func(t *testing.T) {
		// Free external URL -> rejected
		badURL := map[string]any{
			"reason":    "Valid ops reason",
			"audience":  map[string]any{"kind": "role", "role": "customers"},
			"title":     map[string]string{"en": "Maintenance", "ar": "صيانة"},
			"body":      map[string]string{"en": "Check status", "ar": "تابع الحالة"},
			"deep_link": "https://malicious.com/phish",
		}
		rec := makeRequest(http.MethodPost, sendEndpoint, badURL, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "invalid_deep_link") {
			t.Errorf("expected 400 invalid_deep_link for free URL, got %d: %s", rec.Code, rec.Body.String())
		}

		// Valid internal route -> accepted
		validRoute := map[string]any{
			"reason":    "Valid ops reason",
			"audience":  map[string]any{"kind": "role", "role": "customers"},
			"title":     map[string]string{"en": "Order Update", "ar": "تحديث الطلب"},
			"body":      map[string]string{"en": "Check order status", "ar": "تابع حالة طلبك"},
			"deep_link": "/orders/order-123",
			"dry_run":   true,
		}
		rec = makeRequest(http.MethodPost, sendEndpoint, validRoute, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusOK {
			t.Errorf("expected 200 OK for valid /orders route dry run, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 5. Dry Run
	t.Run("Dry run mode", func(t *testing.T) {
		dryRunPayload := map[string]any{
			"reason":   "Capacity check",
			"audience": map[string]any{"kind": "role", "role": "customers"},
			"title":    map[string]string{"en": "Test", "ar": "تجربة"},
			"body":     map[string]string{"en": "Body", "ar": "نص"},
			"dry_run":  true,
		}
		rec := makeRequest(http.MethodPost, sendEndpoint, dryRunPayload, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK for dry run, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp["dry_run"] != true {
			t.Errorf("expected dry_run=true, got %v", resp["dry_run"])
		}
		if resp["audience_size"].(float64) != 3 {
			t.Errorf("expected audience_size=3, got %v", resp["audience_size"])
		}
	})

	// 6. Confirmation Required for "everyone" and audience >= 1000
	t.Run("Confirmation check", func(t *testing.T) {
		everyonePayload := map[string]any{
			"reason":   "Emergency platform update",
			"audience": map[string]any{"kind": "everyone"},
			"title":    map[string]string{"en": "Update", "ar": "تحديث"},
			"body":     map[string]string{"en": "Please update your app", "ar": "يرجى تحديث التطبيق"},
		}
		// Without confirmation field
		rec := makeRequest(http.MethodPost, sendEndpoint, everyonePayload, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "confirmation_required") {
			t.Errorf("expected 400 confirmation_required for everyone audience, got %d: %s", rec.Code, rec.Body.String())
		}

		// With wrong confirmation size
		everyonePayload["confirm_audience_size"] = 999
		rec = makeRequest(http.MethodPost, sendEndpoint, everyonePayload, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "confirmation_required") {
			t.Errorf("expected 400 confirmation_required for mismatching size, got %d: %s", rec.Code, rec.Body.String())
		}

		// With correct confirmation size (1200) -> succeeds
		everyonePayload["confirm_audience_size"] = 1200
		everyonePayload["idempotency_key"] = "test-everyone-send-1"
		rec = makeRequest(http.MethodPost, sendEndpoint, everyonePayload, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusAccepted {
			t.Fatalf("expected 202 Accepted with correct confirmation size, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 7. Idempotency Key Replay
	t.Run("Idempotency key deduplication", func(t *testing.T) {
		idempotencyKey := "idem-key-test-12345"
		payload := map[string]any{
			"idempotency_key": idempotencyKey,
			"reason":          "Tenant broadcast",
			"audience":        map[string]any{"kind": "tenant", "tenant_id": "tenant-alpha"},
			"title":           map[string]string{"en": "Notice", "ar": "إشعار"},
			"body":            map[string]string{"en": "New policy", "ar": "سياسة جديدة"},
		}

		rec1 := makeRequest(http.MethodPost, sendEndpoint, payload, "test-internal-token-456", validRevToken)
		if rec1.Code != http.StatusAccepted {
			t.Fatalf("first request expected 202 Accepted, got %d: %s", rec1.Code, rec1.Body.String())
		}
		var resp1 map[string]any
		_ = json.NewDecoder(rec1.Body).Decode(&resp1)
		jobID1 := resp1["job_id"].(string)

		// Second request with same idempotency key
		rec2 := makeRequest(http.MethodPost, sendEndpoint, payload, "test-internal-token-456", validRevToken)
		if rec2.Code != http.StatusOK {
			t.Fatalf("second idempotent request expected 200 OK, got %d: %s", rec2.Code, rec2.Body.String())
		}
		var resp2 map[string]any
		_ = json.NewDecoder(rec2.Body).Decode(&resp2)
		if resp2["job_id"] != jobID1 {
			t.Errorf("expected same job_id %s, got %v", jobID1, resp2["job_id"])
		}
	})

	// 8. "Send test to me" (test_user_id override)
	t.Run("Send test to me", func(t *testing.T) {
		testPayload := map[string]any{
			"reason":       "Pre-flight test dispatch",
			"audience":     map[string]any{"kind": "everyone"},
			"test_user_id": "reviewer-personal-acct",
			"title":        map[string]string{"en": "Test Title", "ar": "عنوان تجريبي"},
			"body":         map[string]string{"en": "Test Body", "ar": "نص تجريبي"},
		}
		rec := makeRequest(http.MethodPost, sendEndpoint, testPayload, "test-internal-token-456", validRevToken)
		if rec.Code != http.StatusAccepted {
			t.Fatalf("expected 202 Accepted for test send, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp["audience_size"].(float64) != 1 {
			t.Errorf("expected audience_size 1 for test send, got %v", resp["audience_size"])
		}
	})

	// 9. Sends List and Detail Endpoints
	t.Run("Sends list and detail", func(t *testing.T) {
		recList := makeRequest(http.MethodGet, "/admin/notifications/sends", nil, "test-internal-token-456", validRevToken)
		if recList.Code != http.StatusOK {
			t.Fatalf("expected 200 OK for sends list, got %d: %s", recList.Code, recList.Body.String())
		}
		var listResp struct {
			Sends []store.AdminNotificationSend `json:"sends"`
			Total int                           `json:"total"`
		}
		_ = json.NewDecoder(recList.Body).Decode(&listResp)
		if listResp.Total == 0 || len(listResp.Sends) == 0 {
			t.Fatalf("expected non-empty sends list, got %d items", listResp.Total)
		}

		targetID := listResp.Sends[0].ID
		recDetail := makeRequest(http.MethodGet, "/admin/notifications/sends/"+targetID, nil, "test-internal-token-456", validRevToken)
		if recDetail.Code != http.StatusOK {
			t.Fatalf("expected 200 OK for send detail, got %d: %s", recDetail.Code, recDetail.Body.String())
		}
		var detailResp store.AdminNotificationSend
		_ = json.NewDecoder(recDetail.Body).Decode(&detailResp)
		if detailResp.ID != targetID {
			t.Errorf("expected job ID %s, got %s", targetID, detailResp.ID)
		}
	})

	// 10. Template AR/EN Localization
	t.Run("Admin announcement template localization", func(t *testing.T) {
		params := map[string]string{
			"title_ar":  "عنوان عربي",
			"body_ar":   "نص عربي",
			"title_en":  "English Title",
			"body_en":   "English Body",
			"deep_link": "/plan",
		}

		renderedAR, okAR := templates.Render("admin_announcement", "ar", params)
		if !okAR {
			t.Fatalf("expected templates.Render to succeed for Arabic")
		}
		if renderedAR.Title != "عنوان عربي" || renderedAR.Body != "نص عربي" {
			t.Errorf("unexpected Arabic text: %+v", renderedAR)
		}

		renderedEN, okEN := templates.Render("admin_announcement", "en", params)
		if !okEN {
			t.Fatalf("expected templates.Render to succeed for English")
		}
		if renderedEN.Title != "English Title" || renderedEN.Body != "English Body" {
			t.Errorf("unexpected English text: %+v", renderedEN)
		}

		all := templates.RenderAll("admin_announcement", params)
		if all == nil || len(all) != 2 {
			t.Fatalf("expected RenderAll to return 2 locales, got %+v", all)
		}
	})

	// 11. Reviewer Rate Limiting (5 sends / hour)
	t.Run("Reviewer rate limit", func(t *testing.T) {
		// We already performed 3 successful sends above. Let's make 2 more to hit limit = 5.
		for i := 0; i < 2; i++ {
			p := map[string]any{
				"reason":   fmt.Sprintf("Rate limit run %d", i),
				"audience": map[string]any{"kind": "user", "user_id": "cust-1"},
				"title":    map[string]string{"en": "Notice", "ar": "إشعار"},
				"body":     map[string]string{"en": "Text", "ar": "نص"},
			}
			rec := makeRequest(http.MethodPost, sendEndpoint, p, "test-internal-token-456", validRevToken)
			if rec.Code != http.StatusAccepted {
				t.Fatalf("send %d failed with status %d: %s", i, rec.Code, rec.Body.String())
			}
		}

		// 6th send should be rejected with 429 Too Many Requests
		p6 := map[string]any{
			"reason":   "Should be rate limited",
			"audience": map[string]any{"kind": "user", "user_id": "cust-1"},
			"title":    map[string]string{"en": "Notice", "ar": "إشعار"},
			"body":     map[string]string{"en": "Text", "ar": "نص"},
		}
		rec6 := makeRequest(http.MethodPost, sendEndpoint, p6, "test-internal-token-456", validRevToken)
		if rec6.Code != http.StatusTooManyRequests || !strings.Contains(rec6.Body.String(), "rate_limit_exceeded") {
			t.Fatalf("expected 429 rate_limit_exceeded on 6th send, got %d: %s", rec6.Code, rec6.Body.String())
		}
	})
}
