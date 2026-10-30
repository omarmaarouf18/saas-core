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

	"github.com/project/user-service/internal/models"
)

func TestAdminServices_AuthenticationAndValidation(t *testing.T) {
	svc, _, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}

	mux := http.NewServeMux()
	svc.RegisterRoutes(mux)

	// 1. Unauthenticated requests
	endpoints := []struct {
		method string
		url    string
		body   any
	}{
		{http.MethodGet, "/admin/services", nil},
		{http.MethodPost, "/admin/services/svc-1/hide", map[string]string{"reason": "test"}},
		{http.MethodPost, "/admin/services/svc-1/unhide", map[string]string{"reason": "test"}},
		{http.MethodPost, "/admin/services/svc-1/photo/remove", map[string]string{"reason": "test"}},
	}
	for _, ep := range endpoints {
		var req *http.Request
		if ep.body != nil {
			b, _ := json.Marshal(ep.body)
			req = httptest.NewRequest(ep.method, ep.url, bytes.NewReader(b))
		} else {
			req = httptest.NewRequest(ep.method, ep.url, nil)
		}
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 for %s %s without auth, got %d", ep.method, ep.url, rec.Code)
		}
	}

	// 2. Missing reason on hide
	reqBody, _ := json.Marshal(map[string]string{"reason": ""})
	req := httptest.NewRequest(http.MethodPost, "/admin/services/svc-1/hide", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for empty reason on hide, got %d", rec.Code)
	}

	// 3. Reason > 1000 characters
	longReason := strings.Repeat("M", 1001)
	reqBody, _ = json.Marshal(map[string]string{"reason": longReason})
	req = httptest.NewRequest(http.MethodPost, "/admin/services/svc-1/hide", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for >1000 char reason, got %d", rec.Code)
	}

	// 4. Service not found
	reqBody, _ = json.Marshal(map[string]string{"reason": "Inappropriate content"})
	req = httptest.NewRequest(http.MethodPost, "/admin/services/non-existent-svc/hide", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for non-existent service, got %d", rec.Code)
	}
}

func TestAdminServices_ListingAndFilters(t *testing.T) {
	svc, mongoStore, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}

	ctx := context.Background()
	mux := http.NewServeMux()
	svc.RegisterRoutes(mux)

	// Seed services
	svc1 := models.Service{
		ID:              "svc-listing-1",
		TenantID:        "tenant-listing-A",
		Name:            "Fast Food Courier",
		Category:        "food",
		TenantBasePrice: 15.0,
		PhotoURL:        "services/svc-listing-1/photo_123.jpg",
		Latitude:        30.0444,
		Longitude:       31.2357,
	}
	svc2 := models.Service{
		ID:              "svc-listing-2",
		TenantID:        "tenant-listing-A",
		Name:            "Grocery Transport",
		Category:        "grocery",
		TenantBasePrice: 20.0,
		PhotoURL:        "",
		IsHidden:        true,
		HiddenReason:    "Policy violation",
		Latitude:        30.0444,
		Longitude:       31.2357,
	}
	svc3 := models.Service{
		ID:              "svc-listing-3",
		TenantID:        "tenant-listing-B",
		Name:            "Heavy Cargo Freight",
		Category:        "freight",
		TenantBasePrice: 100.0,
		PhotoURL:        "services/svc-listing-3/photo_abc.png",
		Latitude:        30.0444,
		Longitude:       31.2357,
	}

	for _, s := range []*models.Service{&svc1, &svc2, &svc3} {
		if err := mongoStore.CreateService(ctx, s); err != nil {
			t.Fatalf("failed to create service: %v", err)
		}
	}

	// 1. List all services
	req := httptest.NewRequest(http.MethodGet, "/admin/services", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 from /admin/services, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Services []models.Service `json:"services"`
		Total    int64            `json:"total"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}
	if resp.Total != 3 {
		t.Errorf("expected 3 total services, got %d", resp.Total)
	}

	// 2. Filter by tenant_id
	req = httptest.NewRequest(http.MethodGet, "/admin/services?tenant_id=tenant-listing-A", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}
	if resp.Total != 2 {
		t.Errorf("expected 2 services for tenant-listing-A, got %d", resp.Total)
	}

	// 3. Filter by name (case-insensitive)
	req = httptest.NewRequest(http.MethodGet, "/admin/services?name=cargo", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}
	if resp.Total != 1 || resp.Services[0].ID != "svc-listing-3" {
		t.Errorf("expected svc-listing-3 for name=cargo, got %+v", resp.Services)
	}

	// 4. Filter by has_photo=true
	req = httptest.NewRequest(http.MethodGet, "/admin/services?has_photo=true", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}
	if resp.Total != 2 {
		t.Errorf("expected 2 services with photo, got %d", resp.Total)
	}

	// 5. Filter by hidden=true
	req = httptest.NewRequest(http.MethodGet, "/admin/services?hidden=true", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}
	if resp.Total != 1 || resp.Services[0].ID != "svc-listing-2" {
		t.Errorf("expected 1 hidden service, got %+v", resp.Services)
	}
}

func TestAdminServices_HideUnhide_AndMarketplaceExclusion(t *testing.T) {
	svc, mongoStore, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}

	ctx := context.Background()
	mux := http.NewServeMux()
	svc.RegisterRoutes(mux)

	// Seed subscription for tenant so it's open
	sub := models.Subscription{
		ID:        "sub-mod-1",
		TenantID:  "tenant-mod-1",
		Tier:      models.PlanPaid,
		StartedAt: time.Now().UTC(),
		ExpiresAt: time.Now().UTC().Add(24 * time.Hour),
	}
	_ = mongoStore.UpsertSubscription(ctx, &sub)

	testSvc := models.Service{
		ID:              "svc-mod-test-1",
		TenantID:        "tenant-mod-1",
		Name:            "Moderation Service",
		Category:        "delivery",
		TenantBasePrice: 20.0,
		Latitude:        30.0444,
		Longitude:       31.2357,
	}
	if err := mongoStore.CreateService(ctx, &testSvc); err != nil {
		t.Fatalf("failed to create service: %v", err)
	}

	// 1. Initial state: service is visible in marketplace
	req := httptest.NewRequest(http.MethodGet, "/users/services", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 from marketplace, got %d", rec.Code)
	}
	var mktResp struct {
		Count    int                       `json:"count"`
		Services []models.ServiceWithPrice `json:"services"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &mktResp); err != nil {
		t.Fatalf("failed to parse marketplace response: %v", err)
	}
	found := false
	for _, s := range mktResp.Services {
		if s.Service.ID == "svc-mod-test-1" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected svc-mod-test-1 to be present in initial marketplace listing")
	}

	// 2. Hide service via admin
	reqBody, _ := json.Marshal(map[string]string{
		"reason": "Copyright infringement in service description",
	})
	req = httptest.NewRequest(http.MethodPost, "/admin/services/svc-mod-test-1/hide", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on hide service, got %d: %s", rec.Code, rec.Body.String())
	}

	var hideResp struct {
		Success      bool   `json:"success"`
		ServiceID    string `json:"service_id"`
		IsHidden     bool   `json:"is_hidden"`
		HiddenReason string `json:"hidden_reason"`
		HiddenNotice string `json:"hidden_notice"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &hideResp); err != nil {
		t.Fatalf("failed to parse hide response: %v", err)
	}
	if !hideResp.IsHidden || hideResp.HiddenNotice != "hidden by support: Copyright infringement in service description" {
		t.Errorf("unexpected hide response: %+v", hideResp)
	}

	// 3. Marketplace exclusion: MUST NOT appear in GET /users/services
	req = httptest.NewRequest(http.MethodGet, "/users/services", nil)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	var mktResp2 struct {
		Count    int                       `json:"count"`
		Services []models.ServiceWithPrice `json:"services"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &mktResp2)
	for _, s := range mktResp2.Services {
		if s.Service.ID == "svc-mod-test-1" {
			t.Fatalf("hidden service svc-mod-test-1 must be excluded from marketplace listing")
		}
	}

	// 4. Public direct lookup: GET /users/services?id=svc-mod-test-1 without owner auth -> 404
	req = httptest.NewRequest(http.MethodGet, "/users/services?id=svc-mod-test-1", nil)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("expected 404 for public lookup of hidden service, got %d", rec.Code)
	}

	// 5. Owner direct lookup: GET /users/services?id=svc-mod-test-1 with owner auth -> 200 + hidden notice
	req = httptest.NewRequest(http.MethodGet, "/users/services?id=svc-mod-test-1&owner_id=tenant-mod-1", nil)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for owner lookup of hidden service, got %d: %s", rec.Code, rec.Body.String())
	}
	var ownerSvcResp struct {
		Service models.Service `json:"service"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &ownerSvcResp); err != nil {
		t.Fatalf("failed to parse owner service response: %v", err)
	}
	if !ownerSvcResp.Service.IsHidden {
		t.Errorf("expected is_hidden=true for owner view")
	}
	if !strings.Contains(ownerSvcResp.Service.HiddenNotice, "hidden by support") {
		t.Errorf("expected hidden_notice to contain 'hidden by support', got %q", ownerSvcResp.Service.HiddenNotice)
	}

	// 6. Unhide service via admin
	reqBody, _ = json.Marshal(map[string]string{
		"reason": "Owner updated description, approved",
	})
	req = httptest.NewRequest(http.MethodPost, "/admin/services/svc-mod-test-1/unhide", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on unhide service, got %d: %s", rec.Code, rec.Body.String())
	}

	// 7. Verify service is restored in marketplace
	req = httptest.NewRequest(http.MethodGet, "/users/services", nil)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	var mktResp3 struct {
		Services []models.ServiceWithPrice `json:"services"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &mktResp3)
	restoredFound := false
	for _, s := range mktResp3.Services {
		if s.Service.ID == "svc-mod-test-1" {
			restoredFound = true
			break
		}
	}
	if !restoredFound {
		t.Fatalf("expected svc-mod-test-1 to be restored in marketplace after unhide")
	}
}

func TestAdminServices_RemovePhoto(t *testing.T) {
	svc, mongoStore, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}

	ctx := context.Background()
	mux := http.NewServeMux()
	svc.RegisterRoutes(mux)

	// 1. Service without photo -> 400
	noPhotoSvc := models.Service{
		ID:              "svc-no-photo",
		TenantID:        "tenant-photo-test",
		Name:            "No Photo Svc",
		TenantBasePrice: 20.0,
		Latitude:        30.0444,
		Longitude:       31.2357,
	}
	if err := mongoStore.CreateService(ctx, &noPhotoSvc); err != nil {
		t.Fatalf("failed to create service: %v", err)
	}

	reqBody, _ := json.Marshal(map[string]string{
		"reason": "Remove non-existent photo",
	})
	req := httptest.NewRequest(http.MethodPost, "/admin/services/svc-no-photo/photo/remove", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 when removing photo from service with no photo, got %d", rec.Code)
	}

	// 2. Service with photo -> 200, photo_url cleared
	withPhotoSvc := models.Service{
		ID:              "svc-with-photo",
		TenantID:        "tenant-photo-test",
		Name:            "With Photo Svc",
		TenantBasePrice: 20.0,
		PhotoURL:        "services/svc-with-photo/photo_xyz.jpg",
		Latitude:        30.0444,
		Longitude:       31.2357,
	}
	if err := mongoStore.CreateService(ctx, &withPhotoSvc); err != nil {
		t.Fatalf("failed to create service: %v", err)
	}

	reqBody, _ = json.Marshal(map[string]string{
		"reason": "Image contains offensive material",
	})
	req = httptest.NewRequest(http.MethodPost, "/users/admin/services/svc-with-photo/photo/remove", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on photo remove, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify photo_url is cleared in database
	dbSvc := mongoStore.GetServiceByID(ctx, "svc-with-photo")
	if dbSvc == nil || dbSvc.PhotoURL != "" {
		t.Errorf("expected photo_url to be empty, got %q", dbSvc.PhotoURL)
	}
}
