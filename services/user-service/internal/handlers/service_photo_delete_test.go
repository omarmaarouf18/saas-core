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

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// BE-GAPS-FIX item 4: removing the service photo the way the app does it
// (PUT /users/services photo_url: "") clears the field AND deletes the
// stored object; replacing it deletes the old object too. Only keys of
// this tenant are deleted, and only by the owning tenant.
func TestServicePhoto_RemoveAndReplaceDeleteStoredObject(t *testing.T) {
	u, s, ownerID, ownerToken, _ := setupPhotoTestService(t)
	ctx := context.Background()

	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-photo-del", TenantID: ownerID, Name: "Photo Del", Category: "delivery",
		TenantBasePrice: 10, TenantPricePerKM: 1, Latitude: 30.0444, Longitude: 31.2357,
	})

	upload := func(format, path string) string {
		t.Helper()
		ct := "image/jpeg"
		if format == "png" {
			ct = "image/png"
		}
		req := httptest.NewRequest("POST", path, bytes.NewReader(createTestImage(format)))
		req.Header.Set("Content-Type", ct)
		req.Header.Set("Authorization", "Bearer "+ownerToken)
		rec := httptest.NewRecorder()
		u.UploadServicePhoto(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("upload %s: %d %s", path, rec.Code, rec.Body.String())
		}
		var body struct {
			PhotoURL string `json:"photo_url"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		return body.PhotoURL
	}
	put := func(token string, photoURL string) *httptest.ResponseRecorder {
		t.Helper()
		raw, _ := json.Marshal(map[string]any{"id": "svc-photo-del", "photo_url": photoURL})
		req := httptest.NewRequest("PUT", "/users/services", bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()
		u.UpdateService(rec, req)
		return rec
	}
	exists := func(key string) bool {
		rc, err := u.storage.OpenFile(key)
		if err != nil {
			return false
		}
		_ = rc.Close()
		return true
	}
	photoOf := func() string {
		svc := s.GetServiceByID(ctx, "svc-photo-del")
		if svc == nil {
			t.Fatalf("service gone")
		}
		return svc.PhotoURL
	}

	// 1. Remove: field cleared and object deleted.
	jpgKey := upload("jpeg", "/users/services/svc-photo-del/photo")
	if !exists(jpgKey) || photoOf() != jpgKey {
		t.Fatalf("upload did not store %q (field %q)", jpgKey, photoOf())
	}
	if rec := put(ownerToken, ""); rec.Code != http.StatusOK {
		t.Fatalf("PUT photo_url \"\": %d %s", rec.Code, rec.Body.String())
	}
	if photoOf() != "" {
		t.Errorf("photo_url not cleared: %q", photoOf())
	}
	if exists(jpgKey) {
		t.Errorf("stored object %q still exists after removal", jpgKey)
	}

	// 2. Replace jpg by png through upload: the old object is deleted.
	jpgKey = upload("jpeg", "/users/services/svc-photo-del/photo")
	pngKey := upload("png", "/users/services/svc-photo-del/photo")
	if exists(jpgKey) || !exists(pngKey) || photoOf() != pngKey {
		t.Errorf("replace: old exists=%v new exists=%v field=%q", exists(jpgKey), exists(pngKey), photoOf())
	}

	// 3. Replace through PUT with a key uploaded before the service
	// existed (services/<owner>/...): the previous object is deleted, and
	// removing that one deletes it too.
	preKey := upload("jpeg", "/users/services/photo")
	if !strings.HasPrefix(preKey, "services/"+ownerID+"/") {
		t.Fatalf("unexpected pre-create key %q", preKey)
	}
	if rec := put(ownerToken, preKey); rec.Code != http.StatusOK {
		t.Fatalf("PUT pre-create key: %d %s", rec.Code, rec.Body.String())
	}
	if exists(pngKey) {
		t.Errorf("replaced object %q still exists", pngKey)
	}
	if rec := put(ownerToken, ""); rec.Code != http.StatusOK || exists(preKey) {
		t.Errorf("removing the pre-create key: code %d, exists %v", rec.Code, exists(preKey))
	}

	// 4. A key of another tenant pointed at by photo_url is never deleted.
	otherKey := "services/other-tenant-svc/photo.jpg"
	if err := u.storage.Upload(ctx, otherKey, bytes.NewReader(createTestImage("jpeg")), "image/jpeg"); err != nil {
		t.Fatalf("seed other tenant object: %v", err)
	}
	if rec := put(ownerToken, otherKey); rec.Code != http.StatusOK {
		t.Fatalf("PUT other key: %d %s", rec.Code, rec.Body.String())
	}
	if rec := put(ownerToken, ""); rec.Code != http.StatusOK {
		t.Fatalf("PUT clear: %d %s", rec.Code, rec.Body.String())
	}
	if !exists(otherKey) {
		t.Errorf("another tenant's object was deleted")
	}

	// 5. Tenant check: another owner cannot remove this service's photo.
	keepKey := upload("jpeg", "/users/services/svc-photo-del/photo")
	if err := s.UpsertSubscription(ctx, &models.Subscription{
		TenantID: "photo-owner-2", Tier: models.PlanPaid, ExpiresAt: time.Now().Add(24 * time.Hour),
	}); err != nil {
		t.Fatalf("seed subscription: %v", err)
	}
	otherToken, _ := jwtutil.GenerateToken("photo-owner-2", "owner", "photo-owner-2", "o2@example.com")
	if rec := put(otherToken, ""); rec.Code != http.StatusForbidden {
		t.Errorf("other owner PUT: expected 403, got %d %s", rec.Code, rec.Body.String())
	}
	if !exists(keepKey) || photoOf() != keepKey {
		t.Errorf("other owner's request changed the photo: exists=%v field=%q", exists(keepKey), photoOf())
	}
}
