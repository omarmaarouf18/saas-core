package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// BE-GAPS-FIX item 5: a saved address label must be non-empty after trim
// and at most 100 runes (ADR-0028 §2.8, the app's limit). Before, an empty
// or whitespace-only label was stored as "".
func TestSavedAddresses_LabelRequiredAndMax100Runes(t *testing.T) {
	a, s, userID, token, cleanup := setupSavedAddressesTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	mux := http.NewServeMux()
	a.RegisterRoutes(mux)

	send := func(label string) *httptest.ResponseRecorder {
		body, _ := json.Marshal(map[string]any{"saved_addresses": []map[string]any{
			{"label": label, "address": "15 شارع النيل", "lat": 30.0, "lng": 31.0},
		}})
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec
	}

	for _, label := range []string{"", "   ", "\t\n"} {
		rec := send(label)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "label is required") {
			t.Errorf("label %q: expected 400 label is required, got %d: %s", label, rec.Code, rec.Body.String())
		}
	}
	user := s.GetByID(context.Background(), userID)
	if user != nil && len(user.SavedAddresses) != 0 {
		t.Fatalf("rejected writes must not store anything, got %+v", user.SavedAddresses)
	}

	if rec := send(strings.Repeat("ب", 101)); rec.Code != http.StatusBadRequest {
		t.Errorf("101-rune label: expected 400, got %d: %s", rec.Code, rec.Body.String())
	}

	// 100 Arabic runes (200 bytes) is allowed; the label is stored trimmed.
	if rec := send("  " + strings.Repeat("ب", 100) + "  "); rec.Code != http.StatusOK {
		t.Fatalf("100-rune label: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	user = s.GetByID(context.Background(), userID)
	if user == nil || len(user.SavedAddresses) != 1 || user.SavedAddresses[0].Label != strings.Repeat("ب", 100) {
		t.Fatalf("expected the trimmed 100-rune label stored, got %+v", user)
	}
}
