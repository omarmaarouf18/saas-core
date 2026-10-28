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

// TestServicePhotoURL_LegacyAppBuilds: a 1.x build (X-App-Version below
// 2.0.0) that sends a device path or URL as photo_url gets the service
// created without a photo / updated with photo_url unchanged, instead of
// 400. 2.0.0+ builds and requests without the header keep the 400. A value
// in the storage key space (another tenant's key, a traversal) is always
// rejected, whatever the version.
func TestServicePhotoURL_LegacyAppBuilds(t *testing.T) {
	u, s, ownerID, ownerToken, _ := setupPhotoTestService(t)
	ctx := context.Background()

	const stored = "services/svc-legacy/photo_aa11.jpg"
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-legacy", TenantID: ownerID, Name: "Legacy", Category: "delivery",
		TenantBasePrice: 10, TenantPricePerKM: 1, Latitude: 30.0444, Longitude: 31.2357,
		PhotoURL: stored,
	})

	send := func(method, version string, body map[string]any) *httptest.ResponseRecorder {
		t.Helper()
		raw, _ := json.Marshal(body)
		req := httptest.NewRequest(method, "/users/services", bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+ownerToken)
		if version != "" {
			req.Header.Set("X-App-Version", version)
		}
		rec := httptest.NewRecorder()
		if method == http.MethodPost {
			u.CreateService(rec, req)
		} else {
			u.UpdateService(rec, req)
		}
		return rec
	}
	create := func(version, photo string) *httptest.ResponseRecorder {
		return send(http.MethodPost, version, map[string]any{
			"name": "New", "category": "delivery", "tenant_base_price": 10.0, "tenant_price_per_km": 1.0,
			"latitude": 30.0444, "longitude": 31.2357, "photo_url": photo,
		})
	}
	update := func(version, photo string) *httptest.ResponseRecorder {
		return send(http.MethodPut, version, map[string]any{"id": "svc-legacy", "photo_url": photo, "name": "Renamed " + version})
	}
	photoOf := func() string { return s.GetServiceByID(ctx, "svc-legacy").PhotoURL }

	devicePaths := []string{
		"file:///data/user/0/com.qd.app/cache/image_picker123.jpg",
		"/storage/emulated/0/DCIM/shop.jpg",
		"https://cdn.example.com/shop.png",
	}
	for _, version := range []string{"1.4.2", "1.0.0+7", "v1.9.9", "0.9.0"} {
		for _, p := range devicePaths {
			rec := create(version, p)
			if rec.Code != http.StatusCreated {
				t.Fatalf("legacy %s create with %q: %d %s", version, p, rec.Code, rec.Body.String())
			}
			var created struct {
				Service models.Service `json:"service"`
			}
			_ = json.Unmarshal(rec.Body.Bytes(), &created)
			if got := s.GetServiceByID(ctx, created.Service.ID); got == nil || got.PhotoURL != "" {
				t.Fatalf("legacy %s create with %q stored photo_url %+v, want empty", version, p, got)
			}

			rec = update(version, p)
			if rec.Code != http.StatusOK {
				t.Fatalf("legacy %s update with %q: %d %s", version, p, rec.Code, rec.Body.String())
			}
			if photoOf() != stored {
				t.Fatalf("legacy %s update with %q changed photo_url to %q", version, p, photoOf())
			}
			if got := s.GetServiceByID(ctx, "svc-legacy").Name; got != "Renamed "+version {
				t.Fatalf("legacy %s update dropped the other fields: name %q", version, got)
			}
		}
		// An own upload key still works for a legacy build.
		ownKey := "services/svc-legacy/photo_bb22.png"
		if rec := update(version, ownKey); rec.Code != http.StatusOK || photoOf() != ownKey {
			t.Fatalf("legacy %s update with own key: %d stored %q", version, rec.Code, photoOf())
		}
		if rec := update(version, stored); rec.Code != http.StatusOK || photoOf() != stored {
			t.Fatalf("legacy %s restore: %d stored %q", version, rec.Code, photoOf())
		}
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

	// 2.0.0+ and a missing/unparseable header keep the strict 400.
	for _, version := range []string{"2.0.0", "2.0.0+1", "2.3.1", "10.0.0", "", "garbage"} {
		for _, p := range devicePaths {
			assertInvalid(create(version, p), "version "+version+" create with "+p)
			assertInvalid(update(version, p), "version "+version+" update with "+p)
		}
	}

	// The cross-tenant guard is never weakened: storage-space values are
	// rejected for legacy builds too.
	crossTenant := []string{
		"services/svc-other-tenant/photo_0123abcd.jpg",
		"services/photo-owner-2/photo_0123abcd.jpg",
		"/services/photo-owner-2/photo_0123abcd.jpg",
		"./services/photo-owner-2/photo_0123abcd.jpg",
		"services/" + ownerID + "/../svc-other-tenant/photo_0123abcd.jpg",
		"file:///data/../../services/photo-owner-2/photo_0123abcd.jpg",
	}
	for _, version := range []string{"1.4.2", "2.0.0"} {
		for _, k := range crossTenant {
			assertInvalid(create(version, k), "version "+version+" create with "+k)
			assertInvalid(update(version, k), "version "+version+" update with "+k)
		}
	}
	if photoOf() != stored {
		t.Fatalf("photo_url changed to %q", photoOf())
	}
}
