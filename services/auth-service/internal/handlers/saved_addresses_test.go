package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
)

func setupSavedAddressesTest(t *testing.T) (*Auth, *store.MongoDB, string, string, func()) {
	t.Helper()
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return nil, nil, "", "", func() {}
	}

	userID := "usr-saved-addr-1"
	user := &models.User{
		ID:                userID,
		Email:             "saved_addr@example.com",
		Username:          "saved_user",
		Role:              models.RoleUser,
		IsActive:          true,
		FrequentAddresses: []string{"Old frequent 1"},
		CreatedAt:         time.Now(),
	}
	if err := s.CreateUser(context.Background(), user); err != nil {
		t.Fatalf("failed to seed user: %v", err)
	}

	token, _ := jwtutil.GenerateToken(userID, string(models.RoleUser), "", user.Email)

	return a, s, userID, token, cleanup
}

func TestSavedAddresses_PUT_and_PATCH_SyncsFrequentAddresses(t *testing.T) {
	a, s, userID, token, cleanup := setupSavedAddressesTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	mux := http.NewServeMux()
	a.RegisterRoutes(mux)

	// 1. PUT /auth/user with saved_addresses using lat/lng notation
	savedPayload := map[string]any{
		"saved_addresses": []map[string]any{
			{
				"id":           "addr-home",
				"label":        "البيت",
				"address":      "15 شارع النيل، المعادي",
				"address_note": "الدور الثالث، شقة 5",
				"lat":          29.9602,
				"lng":          31.2569,
			},
			{
				"id":           "addr-work",
				"label":        "الشغل",
				"address":      "45 شارع مصدق، الدقي",
				"address_note": "مبنى سرايا الدقي",
				"lat":          30.0381,
				"lng":          31.2057,
			},
		},
	}
	putBody, _ := json.Marshal(savedPayload)
	putReq := httptest.NewRequest(http.MethodPut, "/auth/user", bytes.NewReader(putBody))
	putReq.Header.Set("Authorization", "Bearer "+token)
	putReq.Header.Set("Content-Type", "application/json")
	putRec := httptest.NewRecorder()
	mux.ServeHTTP(putRec, putReq)

	if putRec.Code != http.StatusOK {
		t.Fatalf("PUT /auth/user expected 200, got %d: %s", putRec.Code, putRec.Body.String())
	}

	// 2. Verify stored state directly in database
	dbUser := s.GetByID(context.Background(), userID)
	if dbUser == nil {
		t.Fatalf("user not found in DB")
	}
	if len(dbUser.SavedAddresses) != 2 {
		t.Fatalf("expected 2 saved addresses in DB, got %d", len(dbUser.SavedAddresses))
	}
	if dbUser.SavedAddresses[0].Label != "البيت" || dbUser.SavedAddresses[0].Latitude != 29.9602 || dbUser.SavedAddresses[0].Longitude != 31.2569 {
		t.Errorf("saved address 0 mismatch: %+v", dbUser.SavedAddresses[0])
	}
	if len(dbUser.FrequentAddresses) != 2 {
		t.Fatalf("expected 2 frequent addresses derived in DB, got %d", len(dbUser.FrequentAddresses))
	}
	if dbUser.FrequentAddresses[0] != "15 شارع النيل، المعادي" || dbUser.FrequentAddresses[1] != "45 شارع مصدق، الدقي" {
		t.Errorf("frequent addresses mismatch: %v", dbUser.FrequentAddresses)
	}

	// 3. Verify GET /auth/user returns both saved_addresses and frequent_addresses
	getReq := httptest.NewRequest(http.MethodGet, "/auth/user?id="+token, nil)
	getReq.Header.Set("Authorization", "Bearer "+token)
	getRec := httptest.NewRecorder()
	mux.ServeHTTP(getRec, getReq)

	if getRec.Code != http.StatusOK {
		t.Fatalf("GET /auth/user expected 200, got %d: %s", getRec.Code, getRec.Body.String())
	}

	var getResp struct {
		FrequentAddresses []string              `json:"frequent_addresses"`
		SavedAddresses    []models.SavedAddress `json:"saved_addresses"`
	}
	if err := json.Unmarshal(getRec.Body.Bytes(), &getResp); err != nil {
		t.Fatalf("unmarshal GET response: %v", err)
	}

	if len(getResp.SavedAddresses) != 2 {
		t.Fatalf("GET expected 2 saved_addresses, got %d", len(getResp.SavedAddresses))
	}
	if len(getResp.FrequentAddresses) != 2 {
		t.Fatalf("GET expected 2 frequent_addresses, got %d", len(getResp.FrequentAddresses))
	}
	if getResp.SavedAddresses[0].ID != "addr-home" || getResp.SavedAddresses[0].AddressNote != "الدور الثالث، شقة 5" {
		t.Errorf("GET saved_addresses[0] mismatch: %+v", getResp.SavedAddresses[0])
	}

	// 4. Verify PATCH /auth/user also works with latitude/longitude
	patchPayload := map[string]any{
		"saved_addresses": []map[string]any{
			{
				"id":        "addr-storage",
				"label":     "مخزن",
				"address":   "10 العاشر من رمضان",
				"latitude":  30.3000,
				"longitude": 31.7400,
			},
		},
	}
	patchBody, _ := json.Marshal(patchPayload)
	patchReq := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(patchBody))
	patchReq.Header.Set("Authorization", "Bearer "+token)
	patchReq.Header.Set("Content-Type", "application/json")
	patchRec := httptest.NewRecorder()
	mux.ServeHTTP(patchRec, patchReq)

	if patchRec.Code != http.StatusOK {
		t.Fatalf("PATCH /auth/user expected 200, got %d: %s", patchRec.Code, patchRec.Body.String())
	}

	dbUserAfterPatch := s.GetByID(context.Background(), userID)
	if len(dbUserAfterPatch.SavedAddresses) != 1 || dbUserAfterPatch.SavedAddresses[0].Label != "مخزن" {
		t.Errorf("after PATCH expected 1 saved address ('مخزن'), got %+v", dbUserAfterPatch.SavedAddresses)
	}
	if len(dbUserAfterPatch.FrequentAddresses) != 1 || dbUserAfterPatch.FrequentAddresses[0] != "10 العاشر من رمضان" {
		t.Errorf("after PATCH expected 1 frequent address, got %v", dbUserAfterPatch.FrequentAddresses)
	}
}

func TestSavedAddresses_Validation(t *testing.T) {
	a, _, _, token, cleanup := setupSavedAddressesTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	mux := http.NewServeMux()
	a.RegisterRoutes(mux)

	sendUpdate := func(payload map[string]any) *httptest.ResponseRecorder {
		body, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec
	}

	// Case 1: > 10 entries rejected
	tooMany := make([]map[string]any, 11)
	for i := range tooMany {
		tooMany[i] = map[string]any{
			"label":   fmt.Sprintf("Addr %d", i),
			"address": fmt.Sprintf("Street %d", i),
			"lat":     30.0,
			"lng":     31.0,
		}
	}
	rec1 := sendUpdate(map[string]any{"saved_addresses": tooMany})
	if rec1.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for >10 addresses, got %d: %s", rec1.Code, rec1.Body.String())
	}

	// Case 2: empty address rejected
	rec2 := sendUpdate(map[string]any{
		"saved_addresses": []map[string]any{
			{"label": "Home", "address": "   ", "lat": 30.0, "lng": 31.0},
		},
	})
	if rec2.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for empty address, got %d: %s", rec2.Code, rec2.Body.String())
	}

	// Case 3: invalid latitude (> 90)
	rec3 := sendUpdate(map[string]any{
		"saved_addresses": []map[string]any{
			{"label": "Home", "address": "Valid St", "lat": 95.0, "lng": 31.0},
		},
	})
	if rec3.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for lat=95, got %d: %s", rec3.Code, rec3.Body.String())
	}

	// Case 4: invalid longitude (< -180)
	rec4 := sendUpdate(map[string]any{
		"saved_addresses": []map[string]any{
			{"label": "Home", "address": "Valid St", "lat": 30.0, "lng": -190.0},
		},
	})
	if rec4.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for lng=-190, got %d: %s", rec4.Code, rec4.Body.String())
	}

	// Case 5: address exceeding 250 characters
	longAddr := strings.Repeat("A", 251)
	rec5 := sendUpdate(map[string]any{
		"saved_addresses": []map[string]any{
			{"label": "Home", "address": longAddr, "lat": 30.0, "lng": 31.0},
		},
	})
	if rec5.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for address > 250 runes, got %d: %s", rec5.Code, rec5.Body.String())
	}
}
