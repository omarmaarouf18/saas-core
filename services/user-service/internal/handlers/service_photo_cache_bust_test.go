package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/project/user-service/internal/models"
)

// PROD-PHOTO-STORAGE item 7: every upload gets a new storage key, also when
// the same file type replaces a service's photo, and the replaced object is
// deleted. Uploads before the service exists get distinct keys too.
func TestServicePhoto_ReplaceSameTypeGetsNewKey(t *testing.T) {
	u, s, ownerID, ownerToken, _ := setupPhotoTestService(t)
	ctx := context.Background()
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-cache-bust", TenantID: ownerID, Name: "Cache Bust", Category: "delivery",
		TenantBasePrice: 10, TenantPricePerKM: 1, Latitude: 30.0444, Longitude: 31.2357,
	})

	upload := func(path string) string {
		t.Helper()
		req := httptest.NewRequest("POST", path, bytes.NewReader(createTestImage("jpeg")))
		req.Header.Set("Content-Type", "image/jpeg")
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
	exists := func(key string) bool {
		rc, err := u.storage.OpenFile(key)
		if err != nil {
			return false
		}
		_ = rc.Close()
		return true
	}

	first := upload("/users/services/svc-cache-bust/photo")
	second := upload("/users/services/svc-cache-bust/photo")
	if first == second {
		t.Fatalf("replacing a jpg with a jpg reused the key %q", first)
	}
	for _, k := range []string{first, second} {
		if !strings.HasPrefix(k, "services/svc-cache-bust/photo_") || !strings.HasSuffix(k, ".jpg") || !isOwnPhotoKey(k, "svc-cache-bust") {
			t.Errorf("unexpected key shape %q", k)
		}
	}
	if exists(first) {
		t.Errorf("replaced object %q still exists", first)
	}
	if !exists(second) {
		t.Errorf("new object %q missing", second)
	}
	if got := s.GetServiceByID(ctx, "svc-cache-bust").PhotoURL; got != second {
		t.Errorf("photo_url = %q, want %q", got, second)
	}

	pre1 := upload("/users/services/photo")
	pre2 := upload("/users/services/photo")
	if pre1 == pre2 || !isOwnPhotoKey(pre1, ownerID) || !isOwnPhotoKey(pre2, ownerID) {
		t.Errorf("pre-create uploads: %q and %q must be distinct keys of this owner", pre1, pre2)
	}
}
