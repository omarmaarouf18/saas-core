package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

func setupCustomerNameTest(t *testing.T, authHandler http.HandlerFunc) (*UserService, *store.MongoDB, string, string, string, string) {
	t.Helper()
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	dbName := fmt.Sprintf("saas_user_cust_name_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping: MongoDB not available (%v)", err)
	}
	t.Cleanup(func() {
		_ = s.DropDatabase(context.Background())
		_ = s.Close(context.Background())
	})

	ownerID := "cust-name-owner"
	customerID := "cust-name-customer"
	serviceID := "cust-name-service"

	if err := s.UpsertSubscription(ctx, &models.Subscription{
		TenantID:  ownerID,
		Tier:      models.PlanPaid,
		ExpiresAt: time.Now().Add(24 * time.Hour),
	}); err != nil {
		t.Fatalf("seed subscription: %v", err)
	}

	svc := &models.Service{
		ID:               serviceID,
		TenantID:         ownerID,
		Name:             "Delivery Co",
		Category:         "delivery",
		BasePrice:        20.0,
		TenantBasePrice:  20.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	}
	if err := s.CreateService(ctx, svc); err != nil {
		t.Fatalf("create service: %v", err)
	}

	auth := httptest.NewServer(authHandler)
	t.Cleanup(auth.Close)

	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })

	cfg := &config.Config{
		AuthServiceURL:       auth.URL,
		InternalServiceToken: "mock-internal-token",
		AppEnv:               "test",
		JWTSecret:            os.Getenv("JWT_SECRET"),
	}
	u := NewUserService(s, cfg, rdb)

	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	customerToken, _ := jwtutil.GenerateToken(customerID, "customer", "", "customer@example.com")

	return u, s, ownerID, ownerToken, customerID, customerToken
}

func TestTrackJob_CustomerNameSnapshottedAtBooking(t *testing.T) {
	authHandler := func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		if id == "cust-name-owner" {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":         "cust-name-owner",
				"role":       "owner",
				"kyc_status": "approved",
				"is_active":  true,
				"tenant_id":  "cust-name-owner",
			})
			return
		}
		if id == "cust-name-customer" {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":           "cust-name-customer",
				"role":         "customer",
				"username":     "samir99",
				"display_name": "Samir El-Masry",
				"is_active":    true,
			})
			return
		}
		http.NotFound(w, r)
	}

	u, s, ownerID, ownerToken, customerID, customerToken := setupCustomerNameTest(t, authHandler)

	mux := http.NewServeMux()
	u.RegisterRoutes(mux)

	// Book a job via TrackJob
	bookPayload := map[string]any{
		"owner_id":       ownerToken,
		"service_id":     "cust-name-service",
		"user_id":        customerToken,
		"payment_method": "cod",
		"location": map[string]any{
			"latitude":  30.0444,
			"longitude": 31.2357,
			"address":   "1 Tahrir Square",
		},
		"destination": map[string]any{
			"latitude":  30.0500,
			"longitude": 31.2400,
			"address":   "5 Ramses St",
		},
	}
	bodyBytes, _ := json.Marshal(bookPayload)
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(bodyBytes))
	req.Header.Set("Authorization", "Bearer "+customerToken)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK && rec.Code != http.StatusCreated {
		t.Fatalf("TrackJob expected 200 or 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var trackResp struct {
		Job models.Job `json:"job"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &trackResp); err != nil {
		t.Fatalf("unmarshal trackResp: %v", err)
	}

	jobID := trackResp.Job.ID
	if jobID == "" {
		t.Fatalf("expected job ID")
	}

	// 1. Verify directly in MongoDB that CustomerName is snapshotted
	storedJob := s.GetJob(context.Background(), jobID)
	if storedJob == nil {
		t.Fatalf("job not found in store")
	}
	if storedJob.CustomerName != "Samir El-Masry" {
		t.Errorf("stored job CustomerName = %q, want 'Samir El-Masry'", storedJob.CustomerName)
	}

	// 2. Verify GET /users/jobs/get returns customer_name in OwnerJobResponse
	getReq := httptest.NewRequest("GET", "/users/jobs/get?id="+jobID, nil)
	getReq.Header.Set("Authorization", "Bearer "+ownerToken)
	getRec := httptest.NewRecorder()
	mux.ServeHTTP(getRec, getReq)

	if getRec.Code != http.StatusOK {
		t.Fatalf("GetJob expected 200, got %d: %s", getRec.Code, getRec.Body.String())
	}

	var ownerJobResp models.OwnerJobResponse
	if err := json.Unmarshal(getRec.Body.Bytes(), &ownerJobResp); err != nil {
		t.Fatalf("unmarshal ownerJobResp: %v", err)
	}
	if ownerJobResp.CustomerName != "Samir El-Masry" {
		t.Errorf("GetJob OwnerJobResponse customer_name = %q, want 'Samir El-Masry'", ownerJobResp.CustomerName)
	}

	// 3. Verify GET /users/jobs/owner returns customer_name
	listReq := httptest.NewRequest("GET", "/users/jobs/owner", nil)
	listReq.Header.Set("Authorization", "Bearer "+ownerToken)
	listRec := httptest.NewRecorder()
	mux.ServeHTTP(listRec, listReq)

	if listRec.Code != http.StatusOK {
		t.Fatalf("GetOwnerJobs expected 200, got %d: %s", listRec.Code, listRec.Body.String())
	}

	var ownerJobsList []models.OwnerJobResponse
	if err := json.Unmarshal(listRec.Body.Bytes(), &ownerJobsList); err != nil {
		t.Fatalf("unmarshal ownerJobsList: %v", err)
	}
	if len(ownerJobsList) == 0 {
		t.Fatalf("expected at least 1 job in owner list")
	}
	if ownerJobsList[0].CustomerName != "Samir El-Masry" {
		t.Errorf("GetOwnerJobs customer_name = %q, want 'Samir El-Masry'", ownerJobsList[0].CustomerName)
	}
	_ = customerID
	_ = ownerID
}

func TestOwnerJobResponse_LegacyJob_MemoizedFallback(t *testing.T) {
	var authLookupCount int32
	authHandler := func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		if id == "cust-name-owner" {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":         "cust-name-owner",
				"role":       "owner",
				"kyc_status": "approved",
				"is_active":  true,
				"tenant_id":  "cust-name-owner",
			})
			return
		}
		if id == "legacy-cust-1" {
			atomic.AddInt32(&authLookupCount, 1)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":           "legacy-cust-1",
				"role":         "customer",
				"username":     "legacy_user",
				"display_name": "Legacy Customer",
				"is_active":    true,
			})
			return
		}
		http.NotFound(w, r)
	}

	u, s, ownerID, ownerToken, _, _ := setupCustomerNameTest(t, authHandler)
	mux := http.NewServeMux()
	u.RegisterRoutes(mux)

	ctx := context.Background()
	// Seed 3 legacy jobs with NO CustomerName (empty string) for the same customer
	for i := 1; i <= 3; i++ {
		j := &models.Job{
			ID:            fmt.Sprintf("legacy-job-%d", i),
			OwnerID:       ownerID,
			UserID:        "legacy-cust-1",
			ServiceID:     "cust-name-service",
			Status:        models.JobStatusCompleted,
			CustomerName:  "", // legacy: no snapshotted customer name
			PaymentMethod: "cod",
			Location:      models.Location{Latitude: 30.0444, Longitude: 31.2357},
			Destination:   models.Location{Latitude: 30.0500, Longitude: 31.2400},
			CreatedAt:     time.Now(),
			UpdatedAt:     time.Now(),
		}
		if err := s.CreateJob(ctx, j); err != nil {
			t.Fatalf("seed legacy job: %v", err)
		}
	}

	// Fetch all 3 jobs as owner in one list call
	listReq := httptest.NewRequest("GET", "/users/jobs/owner", nil)
	listReq.Header.Set("Authorization", "Bearer "+ownerToken)
	listRec := httptest.NewRecorder()
	mux.ServeHTTP(listRec, listReq)

	if listRec.Code != http.StatusOK {
		t.Fatalf("GetOwnerJobs expected 200, got %d: %s", listRec.Code, listRec.Body.String())
	}

	var resps []models.OwnerJobResponse
	if err := json.Unmarshal(listRec.Body.Bytes(), &resps); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if len(resps) != 3 {
		t.Fatalf("expected 3 jobs, got %d", len(resps))
	}
	for _, r := range resps {
		if r.CustomerName != "Legacy Customer" {
			t.Errorf("expected customer_name 'Legacy Customer', got %q", r.CustomerName)
		}
	}

	// Verify memoization: auth service should have been queried only ONCE for "legacy-cust-1"
	if lookups := atomic.LoadInt32(&authLookupCount); lookups != 1 {
		t.Errorf("expected exactly 1 S2S lookup for legacy customer across 3 jobs, got %d", lookups)
	}

	// Single job detail GET for legacy job
	getReq := httptest.NewRequest("GET", "/users/jobs/get?id=legacy-job-1", nil)
	getReq.Header.Set("Authorization", "Bearer "+ownerToken)
	getRec := httptest.NewRecorder()
	mux.ServeHTTP(getRec, getReq)
	if getRec.Code != http.StatusOK {
		t.Fatalf("GetJob expected 200, got %d: %s", getRec.Code, getRec.Body.String())
	}
	var singleResp models.OwnerJobResponse
	_ = json.Unmarshal(getRec.Body.Bytes(), &singleResp)
	if singleResp.CustomerName != "Legacy Customer" {
		t.Errorf("GetJob customer_name = %q, want 'Legacy Customer'", singleResp.CustomerName)
	}
}

func TestOwnerJobResponse_LegacyJob_FallbackToNothing(t *testing.T) {
	authHandler := func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		if id == "cust-name-owner" {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":         "cust-name-owner",
				"role":       "owner",
				"kyc_status": "approved",
				"is_active":  true,
				"tenant_id":  "cust-name-owner",
			})
			return
		}
		// Customer does not exist or S2S fails
		http.NotFound(w, r)
	}

	u, s, ownerID, ownerToken, _, _ := setupCustomerNameTest(t, authHandler)
	mux := http.NewServeMux()
	u.RegisterRoutes(mux)

	ctx := context.Background()
	j := &models.Job{
		ID:            "legacy-orphan-job",
		OwnerID:       ownerID,
		UserID:        "non-existent-user",
		ServiceID:     "cust-name-service",
		Status:        models.JobStatusCompleted,
		CustomerName:  "",
		PaymentMethod: "cod",
		Location:      models.Location{Latitude: 30.0444, Longitude: 31.2357},
		Destination:   models.Location{Latitude: 30.0500, Longitude: 31.2400},
		CreatedAt:     time.Now(),
		UpdatedAt:     time.Now(),
	}
	if err := s.CreateJob(ctx, j); err != nil {
		t.Fatalf("seed job: %v", err)
	}

	getReq := httptest.NewRequest("GET", "/users/jobs/get?id=legacy-orphan-job", nil)
	getReq.Header.Set("Authorization", "Bearer "+ownerToken)
	getRec := httptest.NewRecorder()
	mux.ServeHTTP(getRec, getReq)

	if getRec.Code != http.StatusOK {
		t.Fatalf("GetJob expected 200, got %d: %s", getRec.Code, getRec.Body.String())
	}
	var resp models.OwnerJobResponse
	_ = json.Unmarshal(getRec.Body.Bytes(), &resp)
	if resp.CustomerName != "" {
		t.Errorf("expected customer_name to fall back to nothing (''), got %q", resp.CustomerName)
	}
}
