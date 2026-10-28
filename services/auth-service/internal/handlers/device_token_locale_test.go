package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/shared/infra/jwtutil"
)

// PUSH-L10N item 1: POST /auth/device-token stores an optional locale per
// token; a token registered without one (legacy app) keeps none.
func TestDeviceToken_LocalePerToken(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:        "user-device-locale-1",
		Email:     "devicelocale@example.com",
		Username:  "devicelocaleuser",
		Password:  "Password123!",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := mongoStore.CreateUser(ctx, user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	jwt, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	post := func(body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "/auth/device-token", strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+jwt)
		rec := httptest.NewRecorder()
		a.DeviceToken(rec, req)
		return rec
	}
	locales := func() map[string]string {
		got := map[string]string{}
		for _, dt := range mongoStore.GetByID(ctx, user.ID).DeviceTokens {
			got[dt.Token] = dt.Locale
		}
		return got
	}

	for _, body := range []string{
		`{"token":"phone-ar","platform":"android","locale":"ar"}`,
		`{"token":"tablet-en","platform":"android","locale":"en-US"}`,
		`{"token":"legacy","platform":"android"}`,
	} {
		if rec := post(body); rec.Code != http.StatusOK {
			t.Fatalf("register %s: got %d %s", body, rec.Code, rec.Body.String())
		}
	}
	want := map[string]string{"phone-ar": "ar", "tablet-en": "en", "legacy": ""}
	if got := locales(); len(got) != 3 || got["phone-ar"] != "ar" || got["tablet-en"] != "en" || got["legacy"] != "" {
		t.Fatalf("locales after register: got %v, want %v", got, want)
	}

	// The user switches the phone to English: same token, new locale.
	if rec := post(`{"token":"phone-ar","platform":"android","locale":"en"}`); rec.Code != http.StatusOK {
		t.Fatalf("re-register: got %d", rec.Code)
	}
	if got := locales()["phone-ar"]; got != "en" {
		t.Errorf("locale after switch: got %q, want en", got)
	}
	// A re-register without a locale (an old app on that phone) drops it.
	if rec := post(`{"token":"phone-ar","platform":"android"}`); rec.Code != http.StatusOK {
		t.Fatalf("legacy re-register: got %d", rec.Code)
	}
	if got := locales()["phone-ar"]; got != "" {
		t.Errorf("locale after legacy re-register: got %q, want empty", got)
	}

	// Unknown locale: 400, nothing stored.
	rec := post(`{"token":"phone-fr","platform":"android","locale":"fr"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("locale fr: got %d, want 400", rec.Code)
	}
	if _, ok := locales()["phone-fr"]; ok {
		t.Errorf("token with a rejected locale was stored")
	}

	// The internal GET /auth/user (notification-service) carries the locale.
	a.internalServiceToken = "internal-token-locale-test"
	req := httptest.NewRequest("GET", "/auth/user?id="+user.ID, nil)
	req.Header.Set("X-Internal-Token", "internal-token-locale-test")
	getRec := httptest.NewRecorder()
	a.GetUser(getRec, req)
	if getRec.Code != http.StatusOK {
		t.Fatalf("GetUser: got %d %s", getRec.Code, getRec.Body.String())
	}
	var resp struct {
		DeviceTokens []map[string]any `json:"device_tokens"`
	}
	if err := json.Unmarshal(getRec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	seen := map[string]any{}
	for _, dt := range resp.DeviceTokens {
		seen[dt["token"].(string)] = dt["locale"]
	}
	if seen["tablet-en"] != "en" {
		t.Errorf("internal GetUser: tablet-en locale = %v, want en", seen["tablet-en"])
	}
	if v, ok := seen["legacy"]; !ok || v != nil {
		t.Errorf("internal GetUser: legacy token must have no locale key, got %v (present=%v)", v, ok)
	}
}
