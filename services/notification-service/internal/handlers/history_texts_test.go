package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
)

// PUSH-L10N item 3: the stored notification keeps type + params, and the
// history returns them with the title/body in each app language, so the
// app can show its list in the current language. Items without what their
// template needs (older history, unknown types) carry no texts.
func TestHistory_CarriesParamsAndTexts(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init(os.Getenv("JWT_SECRET"))
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	userID, tenantID := "cust-l10n", "tenant-l10n"
	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"id": userID, "tenant_id": tenantID, "role": "client", "is_active": true})
	}))
	defer mockAuth.Close()

	n := NewNotification(hub.NewSSEHub(), newMemoryStore(), &config.Config{
		AuthServiceURL: mockAuth.URL, InternalServiceToken: "itok", AllowedOrigin: "*",
	}, rdb)
	mux := http.NewServeMux()
	n.RegisterRoutes(mux)

	for _, p := range []map[string]any{
		{"type": "job_accepted", "job_id": "job-1", "title": "Courier Assigned",
			"body": "Your courier has accepted! Final fare: EGP 45.50", "params": map[string]string{"fare": "45.50"}},
		{"type": "kyc_rejected", "title": "Verification rejected", "body": "Your KYE verification was rejected. Reason: "},
		{"type": "popup", "title": "Hello", "body": "World"},
	} {
		p["tenant_id"], p["user_id"], p["roles"] = tenantID, userID, []string{"client"}
		if rec := postInternal(mux, "/notifications/send", p); rec.Code != http.StatusOK {
			t.Fatalf("send %v: %d %s", p["type"], rec.Code, rec.Body.String())
		}
	}

	token, _ := jwtutil.GenerateToken(userID, "user", tenantID, "c@example.com")
	req := httptest.NewRequest(http.MethodGet, "/notifications/history?limit=10", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("history: %d %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Notifications []struct {
			Type   string                       `json:"type"`
			Title  string                       `json:"title"`
			Body   string                       `json:"body"`
			Params map[string]string            `json:"params"`
			Texts  map[string]map[string]string `json:"texts"`
		} `json:"notifications"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Notifications) != 3 {
		t.Fatalf("got %d items: %s", len(resp.Notifications), rec.Body.String())
	}
	for _, it := range resp.Notifications {
		switch it.Type {
		case "job_accepted":
			if it.Body != "Your courier has accepted! Final fare: EGP 45.50" || it.Params["fare"] != "45.50" {
				t.Errorf("job_accepted keeps the sender text and params: %+v", it)
			}
			if it.Texts["ar"]["body"] != "الأجرة النهائية: 45.50 ج.م." || it.Texts["en"]["title"] != "A courier accepted your order" {
				t.Errorf("job_accepted texts: %v", it.Texts)
			}
		case "kyc_rejected", "popup":
			if it.Texts != nil {
				t.Errorf("%s: texts without what the template needs: %v", it.Type, it.Texts)
			}
		}
	}

	// SSE carries the same fields (ToClient).
	b, _ := json.Marshal(hub.Notification{Type: "job_picked_up", JobID: "j", Title: "Courier Picked Up", Body: "x"}.ToClient())
	var wire map[string]any
	_ = json.Unmarshal(b, &wire)
	texts, _ := wire["texts"].(map[string]any)
	ar, _ := texts["ar"].(map[string]any)
	if ar["title"] != "طلبك اتستلم" {
		t.Errorf("SSE wire texts: %s", b)
	}
	if bytes.Contains(b, []byte(`"params"`)) {
		t.Errorf("SSE wire: no params, no params key: %s", b)
	}
}
