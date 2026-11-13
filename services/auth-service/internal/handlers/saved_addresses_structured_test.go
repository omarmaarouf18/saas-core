package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
)

func TestSavedAddresses_StructuredDetails_RoundTrip(t *testing.T) {
	a, s, userID, token, cleanup := setupSavedAddressesTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	mux := http.NewServeMux()
	a.RegisterRoutes(mux)

	// 1. PUT /auth/user with building, floor, apartment
	savedPayload := map[string]any{
		"saved_addresses": []map[string]any{
			{
				"id":           "addr-home-struct",
				"label":        "البيت",
				"address":      "15 شارع النيل، المعادي",
				"address_note": "بجوار المسجد",
				"building":     "عمارة 12",
				"floor":        "3",
				"apartment":    "7",
				"lat":          29.9602,
				"lng":          31.2569,
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

	// 2. Verify stored state in DB
	dbUser := s.GetByID(context.Background(), userID)
	if dbUser == nil {
		t.Fatalf("user not found in DB")
	}
	if len(dbUser.SavedAddresses) != 1 {
		t.Fatalf("expected 1 saved address in DB, got %d", len(dbUser.SavedAddresses))
	}
	addr := dbUser.SavedAddresses[0]
	if addr.Building != "عمارة 12" || addr.Floor != "3" || addr.Apartment != "7" {
		t.Errorf("DB structured details mismatch: building=%q, floor=%q, apt=%q", addr.Building, addr.Floor, addr.Apartment)
	}

	// 3. Verify GET /auth/user returns the structured fields
	getReq := httptest.NewRequest(http.MethodGet, "/auth/user", nil)
	getReq.Header.Set("Authorization", "Bearer "+token)
	getRec := httptest.NewRecorder()
	mux.ServeHTTP(getRec, getReq)

	if getRec.Code != http.StatusOK {
		t.Fatalf("GET /auth/user expected 200, got %d: %s", getRec.Code, getRec.Body.String())
	}

	var getResp struct {
		SavedAddresses []models.SavedAddress `json:"saved_addresses"`
	}
	if err := json.Unmarshal(getRec.Body.Bytes(), &getResp); err != nil {
		t.Fatalf("failed to parse GET response: %v", err)
	}
	if len(getResp.SavedAddresses) != 1 {
		t.Fatalf("GET expected 1 saved address, got %d", len(getResp.SavedAddresses))
	}
	getAddr := getResp.SavedAddresses[0]
	if getAddr.Building != "عمارة 12" || getAddr.Floor != "3" || getAddr.Apartment != "7" {
		t.Errorf("GET response structured details mismatch: building=%q, floor=%q, apt=%q", getAddr.Building, getAddr.Floor, getAddr.Apartment)
	}
}

func TestSavedAddresses_StructuredDetails_OverCapRejected(t *testing.T) {
	a, _, _, token, cleanup := setupSavedAddressesTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	mux := http.NewServeMux()
	a.RegisterRoutes(mux)

	sendUpdate := func(payload map[string]any) *httptest.ResponseRecorder {
		body, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPut, "/auth/user", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec
	}

	// 1. Building over 50 runes
	rec1 := sendUpdate(map[string]any{
		"saved_addresses": []map[string]any{
			{
				"label":    "Home",
				"address":  "123 Street",
				"building": strings.Repeat("ع", 51),
				"lat":      30.0,
				"lng":      31.0,
			},
		},
	})
	if rec1.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for building > 50 runes, got %d: %s", rec1.Code, rec1.Body.String())
	}
	if !strings.Contains(rec1.Body.String(), "building cannot exceed 50 characters") {
		t.Errorf("expected building cap error message, got %s", rec1.Body.String())
	}

	// 2. Floor over 20 runes
	rec2 := sendUpdate(map[string]any{
		"saved_addresses": []map[string]any{
			{
				"label":   "Home",
				"address": "123 Street",
				"floor":   strings.Repeat("F", 21),
				"lat":     30.0,
				"lng":     31.0,
			},
		},
	})
	if rec2.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for floor > 20 runes, got %d: %s", rec2.Code, rec2.Body.String())
	}
	if !strings.Contains(rec2.Body.String(), "floor cannot exceed 20 characters") {
		t.Errorf("expected floor cap error message, got %s", rec2.Body.String())
	}

	// 3. Apartment over 20 runes
	rec3 := sendUpdate(map[string]any{
		"saved_addresses": []map[string]any{
			{
				"label":     "Home",
				"address":   "123 Street",
				"apartment": strings.Repeat("A", 21),
				"lat":       30.0,
				"lng":       31.0,
			},
		},
	})
	if rec3.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for apartment > 20 runes, got %d: %s", rec3.Code, rec3.Body.String())
	}
	if !strings.Contains(rec3.Body.String(), "apartment cannot exceed 20 characters") {
		t.Errorf("expected apartment cap error message, got %s", rec3.Body.String())
	}
}

func TestSavedAddresses_StructuredDetails_OldRecordStillLoads(t *testing.T) {
	// JSON payload representing an old record without building, floor, apartment
	oldJSON := `{"id":"addr_old_1","label":"Old Home","address":"42 Old Cairo St","address_note":"Near tree","latitude":30.05,"longitude":31.25}`

	var addr models.SavedAddress
	if err := json.Unmarshal([]byte(oldJSON), &addr); err != nil {
		t.Fatalf("failed to unmarshal old record: %v", err)
	}

	if addr.ID != "addr_old_1" || addr.Label != "Old Home" || addr.Address != "42 Old Cairo St" {
		t.Errorf("unmarshaled old record base fields mismatch: %+v", addr)
	}
	if addr.Building != "" || addr.Floor != "" || addr.Apartment != "" {
		t.Errorf("expected empty string for missing structured fields, got building=%q, floor=%q, apt=%q", addr.Building, addr.Floor, addr.Apartment)
	}

	// Marshaling must omit empty building, floor, apartment (omitempty)
	marshaled, err := json.Marshal(addr)
	if err != nil {
		t.Fatalf("failed to marshal addr: %v", err)
	}
	mStr := string(marshaled)
	if strings.Contains(mStr, "building") || strings.Contains(mStr, "floor") || strings.Contains(mStr, "apartment") {
		t.Errorf("marshaled JSON should omit empty structured fields, got: %s", mStr)
	}

	// DB read test for user seeded with old address without structured fields
	a, s, _, _, cleanup := setupSavedAddressesTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	oldUser := &models.User{
		ID:       "usr-old-rec-1",
		Email:    "oldrec@example.com",
		Username: "oldrec",
		Role:     models.RoleUser,
		IsActive: true,
		SavedAddresses: []models.SavedAddress{
			{
				ID:        "addr-old",
				Label:     "Work",
				Address:   "10 Work St",
				Latitude:  30.1,
				Longitude: 31.1,
			},
		},
		CreatedAt: time.Now(),
	}
	if err := s.CreateUser(context.Background(), oldUser); err != nil {
		t.Fatalf("failed to seed old user: %v", err)
	}

	loaded := s.GetByID(context.Background(), "usr-old-rec-1")
	if loaded == nil || len(loaded.SavedAddresses) != 1 {
		t.Fatalf("failed to load user with old address from DB")
	}
	loadedAddr := loaded.SavedAddresses[0]
	if loadedAddr.Building != "" || loadedAddr.Floor != "" || loadedAddr.Apartment != "" {
		t.Errorf("expected empty structured details on old DB record, got building=%q floor=%q apt=%q", loadedAddr.Building, loadedAddr.Floor, loadedAddr.Apartment)
	}
}

func TestSavedAddresses_StructuredDetails_Sanitization(t *testing.T) {
	a, s, userID, token, cleanup := setupSavedAddressesTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	mux := http.NewServeMux()
	a.RegisterRoutes(mux)

	// Send building/floor/apartment with surrounding spaces and control characters (\x00, \x07)
	savedPayload := map[string]any{
		"saved_addresses": []map[string]any{
			{
				"id":        "addr-clean-test",
				"label":     "Home",
				"address":   "  123 Street  ",
				"building":  "  Bldg \x01 10  ",
				"floor":     "\tFloor 4\n",
				"apartment": "  Apt \x07 2  ",
				"lat":       30.0,
				"lng":       31.0,
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
		t.Fatalf("expected 200, got %d: %s", putRec.Code, putRec.Body.String())
	}

	dbUser := s.GetByID(context.Background(), userID)
	if dbUser == nil || len(dbUser.SavedAddresses) != 1 {
		t.Fatalf("user not found or invalid saved addresses")
	}
	addr := dbUser.SavedAddresses[0]
	if addr.Address != "123 Street" {
		t.Errorf("address not trimmed: %q", addr.Address)
	}
	if addr.Building != "Bldg  10" {
		t.Errorf("building not sanitized: %q", addr.Building)
	}
	if addr.Floor != "Floor 4" {
		t.Errorf("floor not sanitized: %q", addr.Floor)
	}
	if addr.Apartment != "Apt  2" {
		t.Errorf("apartment not sanitized: %q", addr.Apartment)
	}
}
