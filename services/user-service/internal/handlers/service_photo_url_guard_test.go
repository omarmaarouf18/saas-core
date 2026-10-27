package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/user-service/internal/models"
)

// PROD-PHOTO-STORAGE item 6: POST/PUT /users/services accept photo_url only
// when it is empty or a key this tenant's photo upload produced
// (services/<service id>/... or services/<tenant id>/...). Anything else —
// another tenant's key above all — is 400 invalid_photo_url and changes
// nothing.
func TestServicePhotoURL_WriteGuard(t *testing.T) {
	u, s, ownerID, ownerToken, _ := setupPhotoTestService(t)
	ctx := context.Background()

	// Another tenant with its own service and an uploaded photo object.
	const otherOwner = "photo-owner-2"
	if err := s.UpsertSubscription(ctx, &models.Subscription{
		TenantID: otherOwner, Tier: models.PlanPaid, ExpiresAt: time.Now().Add(24 * time.Hour),
	}); err != nil {
		t.Fatalf("seed subscription: %v", err)
	}
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-other-tenant", TenantID: otherOwner, Name: "Other", Category: "delivery",
		TenantBasePrice: 10, TenantPricePerKM: 1, Latitude: 30.0444, Longitude: 31.2357,
	})
	otherServiceKey := "services/svc-other-tenant/photo_0123abcd.jpg"
	otherOwnerKey := "services/" + otherOwner + "/photo_0123abcd.jpg"
	for _, k := range []string{otherServiceKey, otherOwnerKey} {
		if err := u.storage.Upload(ctx, k, bytes.NewReader(createTestImage("jpeg")), "image/jpeg"); err != nil {
			t.Fatalf("seed %s: %v", k, err)
		}
	}

	const legacy = "file:///data/user/0/app/cache/shop.jpg"
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-guard", TenantID: ownerID, Name: "Guard", Category: "delivery",
		TenantBasePrice: 10, TenantPricePerKM: 1, Latitude: 30.0444, Longitude: 31.2357,
		PhotoURL: legacy,
	})

	send := func(method string, body map[string]any) *httptest.ResponseRecorder {
		t.Helper()
		raw, _ := json.Marshal(body)
		req := httptest.NewRequest(method, "/users/services", bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+ownerToken)
		rec := httptest.NewRecorder()
		if method == http.MethodPost {
			u.CreateService(rec, req)
		} else {
			u.UpdateService(rec, req)
		}
		return rec
	}
	create := func(photo string) *httptest.ResponseRecorder {
		return send(http.MethodPost, map[string]any{
			"name": "New", "category": "delivery", "tenant_base_price": 10.0, "tenant_price_per_km": 1.0,
			"latitude": 30.0444, "longitude": 31.2357, "photo_url": photo,
		})
	}
	update := func(photo string) *httptest.ResponseRecorder {
		return send(http.MethodPut, map[string]any{"id": "svc-guard", "photo_url": photo})
	}
	assertInvalid := func(rec *httptest.ResponseRecorder, step string) {
		t.Helper()
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s: expected 400, got %d: %s", step, rec.Code, rec.Body.String())
		}
		var body map[string]string
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		if body["code"] != ErrCodeInvalidPhotoURL {
			t.Errorf("%s: expected code %s, got %s", step, ErrCodeInvalidPhotoURL, rec.Body.String())
		}
	}
	photoOf := func() string {
		return s.GetServiceByID(ctx, "svc-guard").PhotoURL
	}

	rejected := map[string]string{
		"other tenant's service key": otherServiceKey,
		"other tenant's owner key":   otherOwnerKey,
		"https URL":                  "https://evil.example.com/photo.jpg",
		"device path":                "file:///sdcard/photo.jpg",
		"absolute path":              "/etc/passwd",
		"traversal":                  "services/" + ownerID + "/../svc-other-tenant/photo_0123abcd.jpg",
		"nested":                     "services/" + ownerID + "/x/photo.jpg",
		"not a photo name":           "services/" + ownerID + "/kyc.jpg",
		"wrong extension":            "services/" + ownerID + "/photo_1.gif",
	}
	for name, key := range rejected {
		assertInvalid(create(key), "create with "+name)
		assertInvalid(update(key), "update with "+name)
		if photoOf() != legacy {
			t.Fatalf("update with %s changed photo_url to %q", name, photoOf())
		}
	}
	for _, k := range []string{otherServiceKey, otherOwnerKey} {
		if rc, err := u.storage.OpenFile(k); err != nil {
			t.Errorf("other tenant's object %s was touched: %v", k, err)
		} else {
			_ = rc.Close()
		}
	}

	// Resending the stored (legacy) value unchanged is accepted.
	if rec := update(legacy); rec.Code != http.StatusOK {
		t.Fatalf("update with unchanged legacy value: %d %s", rec.Code, rec.Body.String())
	}

	// Own keys: pre-create (services/<owner>/...) on create and update,
	// per-service (services/<service id>/...) on update, and empty.
	ownKey := "services/" + ownerID + "/photo_00ff.png"
	if rec := create(ownKey); rec.Code != http.StatusCreated {
		t.Fatalf("create with own pre-create key: %d %s", rec.Code, rec.Body.String())
	}
	if rec := create(""); rec.Code != http.StatusCreated {
		t.Fatalf("create without photo: %d %s", rec.Code, rec.Body.String())
	}
	for _, k := range []string{ownKey, "services/svc-guard/photo_abc123.jpg", "services/svc-guard/photo.jpg", ""} {
		if rec := update(k); rec.Code != http.StatusOK {
			t.Fatalf("update with %q: %d %s", k, rec.Code, rec.Body.String())
		}
		if photoOf() != k {
			t.Fatalf("update with %q stored %q", k, photoOf())
		}
	}
}
