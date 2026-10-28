package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/project/user-service/internal/models"
)

// PUSH-BE item 4: GET /users/services/{id}/photo answers an ETag derived
// from the storage key, honours If-None-Match with 304, and is cached
// privately for minutes, not a day; the service JSON carries photo_version.
func TestServicePhoto_ETagAndCacheControl(t *testing.T) {
	u, s, ownerID, ownerToken, customerToken := setupPhotoTestService(t)
	ctx := context.Background()

	keyA := "services/" + ownerID + "/photo_aaaa1111.jpg"
	if err := u.storage.Upload(ctx, keyA, bytes.NewReader(createTestImage("jpeg")), "image/jpeg"); err != nil {
		t.Fatalf("seed %s: %v", keyA, err)
	}

	// Create through the API: the service JSON carries photo_version.
	raw, _ := json.Marshal(map[string]any{
		"name": "ETag", "category": "delivery", "tenant_base_price": 10.0, "tenant_price_per_km": 1.0,
		"latitude": 30.0444, "longitude": 31.2357, "photo_url": keyA,
	})
	req := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec := httptest.NewRecorder()
	u.CreateService(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create: %d %s", rec.Code, rec.Body.String())
	}
	var created struct {
		Service map[string]any `json:"service"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &created)
	versionA := models.PhotoVersionOf(keyA)
	if got := created.Service["photo_version"]; got != versionA {
		t.Fatalf("service JSON photo_version = %v, want %q", got, versionA)
	}
	serviceID, _ := created.Service["id"].(string)

	get := func(ifNoneMatch string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(http.MethodGet, "/users/services/"+serviceID+"/photo?v="+versionA, nil)
		req.Header.Set("Authorization", "Bearer "+customerToken)
		if ifNoneMatch != "" {
			req.Header.Set("If-None-Match", ifNoneMatch)
		}
		rec := httptest.NewRecorder()
		u.GetServicePhoto(rec, req)
		return rec
	}

	first := get("")
	if first.Code != http.StatusOK || first.Body.Len() == 0 {
		t.Fatalf("first GET: %d (%d bytes)", first.Code, first.Body.Len())
	}
	etagA := first.Header().Get("ETag")
	if etagA != `"`+versionA+`"` {
		t.Fatalf("ETag = %q, want %q", etagA, `"`+versionA+`"`)
	}
	cc := first.Header().Get("Cache-Control")
	if !strings.Contains(cc, "private") || !strings.Contains(cc, "max-age=") {
		t.Fatalf("Cache-Control = %q, want private with a max-age", cc)
	}
	maxAge, err := strconv.Atoi(strings.TrimSpace(cc[strings.Index(cc, "max-age=")+len("max-age="):]))
	if err != nil || maxAge <= 0 || maxAge > 600 {
		t.Fatalf("Cache-Control %q: max-age must be at most 10 minutes", cc)
	}

	for _, inm := range []string{etagA, "W/" + etagA, `"other", ` + etagA, "*"} {
		rec := get(inm)
		if rec.Code != http.StatusNotModified || rec.Body.Len() != 0 {
			t.Errorf("If-None-Match %s: %d (%d bytes), want 304 with no body", inm, rec.Code, rec.Body.Len())
		}
		if rec.Header().Get("ETag") != etagA {
			t.Errorf("If-None-Match %s: 304 without the ETag", inm)
		}
	}
	if rec := get(`"stale"`); rec.Code != http.StatusOK {
		t.Errorf("non-matching If-None-Match: %d, want 200", rec.Code)
	}

	// Replace the photo (a new upload always gets a new key): the old ETag
	// no longer matches.
	keyB := "services/" + serviceID + "/photo_bbbb2222.png"
	if err := u.storage.Upload(ctx, keyB, bytes.NewReader(createTestImage("png")), "image/png"); err != nil {
		t.Fatalf("seed %s: %v", keyB, err)
	}
	if _, err := s.UpdateServiceFields(ctx, serviceID, ownerID, map[string]any{"photo_url": keyB}); err != nil {
		t.Fatalf("replace photo: %v", err)
	}
	after := get(etagA)
	if after.Code != http.StatusOK {
		t.Fatalf("GET with the old ETag after replace: %d, want 200", after.Code)
	}
	if got, want := after.Header().Get("ETag"), `"`+models.PhotoVersionOf(keyB)+`"`; got != want || got == etagA {
		t.Fatalf("ETag after replace = %q, want %q", got, want)
	}
	if ct := after.Header().Get("Content-Type"); ct != "image/png" {
		t.Errorf("Content-Type after replace = %q", ct)
	}
}
