package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

func setupAdminJobsTestEnv(t *testing.T) (*UserService, *store.MongoDB, string) {
	t.Helper()

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	dbName := fmt.Sprintf("saas_user_jobs_test_%d", time.Now().UnixNano())
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping admin jobs test: MongoDB not available (%v)", err)
		return nil, nil, ""
	}

	validReviewerToken := "valid-reviewer-token"

	// Mock Auth & Notification Service
	mockServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		internalTok := r.Header.Get("X-Internal-Token")
		if internalTok != "test-internal-token" {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"error":"invalid internal token"}`))
			return
		}

		if r.URL.Path == "/auth/reviewer/verify" {
			revTok := r.Header.Get("X-Reviewer-Token")
			if revTok == validReviewerToken {
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"id":"reviewer-jobs-admin","name":"Jobs Ops Admin"}`))
				return
			}
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
			return
		}

		if r.URL.Path == "/auth/user" {
			id := r.URL.Query().Get("id")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":    id,
				"phone": "+201099998888",
			})
			return
		}

		if r.URL.Path == "/auth/internal/user-by-phone" {
			phone := r.URL.Query().Get("phone")
			if phone == "+201033333333" {
				w.WriteHeader(http.StatusOK)
				_ = json.NewEncoder(w).Encode(map[string]any{
					"id":    "user-2",
					"phone": phone,
				})
				return
			}
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":"user not found"}`))
			return
		}

		if r.URL.Path == "/notifications/internal/by-job" {
			jobID := r.URL.Query().Get("job_id")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"job_id": jobID,
				"notifications": []map[string]any{
					{
						"id":        "notif-1",
						"type":      "job_accepted",
						"title":     "Driver Assigned",
						"body":      "Your order has been assigned to a driver",
						"timestamp": time.Now().UTC(),
					},
				},
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))

	t.Cleanup(func() {
		mockServer.Close()
		dropCtx, dropCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer dropCancel()
		_ = mongoStore.DropDatabase(dropCtx)
		_ = mongoStore.Close(dropCtx)
	})

	cfg := &config.Config{
		InternalServiceToken:   "test-internal-token",
		AuthServiceURL:         mockServer.URL,
		NotificationServiceURL: mockServer.URL,
	}

	svc := NewUserService(mongoStore, cfg, nil)
	return svc, mongoStore, validReviewerToken
}

func TestAdminJobs_Authentication(t *testing.T) {
	svc, _, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}

	t.Run("Missing Internal Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs", nil)
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Missing Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Invalid Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", "invalid-token")
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Method Not Allowed", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/admin/jobs", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Errorf("expected 405 Method Not Allowed, got %d", rec.Code)
		}
	})
}

func TestAdminJobs_ListingAndFiltering(t *testing.T) {
	svc, mongoStore, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}
	ctx := context.Background()
	now := time.Now().UTC()

	// Seed 3 jobs
	j1 := &models.Job{
		ID:         "job-alpha-101",
		OwnerID:    "owner-a",
		UserID:     "user-1",
		EmployeeID: "emp-1",
		ServiceID:  "srv-1",
		Status:     models.JobStatusActive,
		SubStatus:  models.SubStatusHeadingToPickup,
		Recipient: &models.JobRecipient{
			Name:  "Ahmed Ali",
			Phone: "+201022222222",
			Notes: "Call on arrival",
		},
		PackageDetails: &models.PackageDetails{
			Size: models.PackageSizeMedium,
		},
		SuggestedPrice: 100.0,
		CreatedAt:      now.Add(-2 * 24 * time.Hour),
	}
	j2 := &models.Job{
		ID:         "job-beta-202",
		OwnerID:    "owner-b",
		UserID:     "user-2",
		EmployeeID: "emp-2",
		ServiceID:  "srv-2",
		Status:     models.JobStatusCompleted,
		Recipient: &models.JobRecipient{
			Name:  "Sarah Omar",
			Phone: "+201044444444",
		},
		PackageDetails: &models.PackageDetails{
			Size: models.PackageSizeSmall,
		},
		SuggestedPrice: 150.0,
		CreatedAt:      now,
	}
	j3 := &models.Job{
		ID:         "job-gamma-303",
		OwnerID:    "owner-a",
		UserID:     "user-3",
		EmployeeID: "emp-1",
		ServiceID:  "srv-1",
		Status:     models.JobStatusCancelled,
		Recipient: &models.JobRecipient{
			Name:  "Mona Hassan",
			Phone: "+201055555555",
		},
		SuggestedPrice: 80.0,
		CreatedAt:      now.Add(-5 * 24 * time.Hour),
	}

	_ = mongoStore.CreateJob(ctx, j1)
	_ = mongoStore.CreateJob(ctx, j2)
	_ = mongoStore.CreateJob(ctx, j3)

	t.Run("List All Jobs", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp AdminJobListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 3 {
			t.Errorf("expected 3 total jobs, got %d", resp.Total)
		}
		// Phones must be visible unmasked
		if len(resp.Jobs) > 0 && resp.Jobs[0].Recipient != nil {
			if resp.Jobs[0].Recipient.Phone == "" {
				t.Errorf("expected unmasked phone, got empty")
			}
		}
	})

	t.Run("Filter by Job ID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs?job_id=job-alpha-101", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)

		var resp AdminJobListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 || resp.Jobs[0].ID != "job-alpha-101" {
			t.Errorf("expected job-alpha-101, got %+v", resp)
		}
	})

	t.Run("Filter by Customer ID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs?customer_id=user-2", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)

		var resp AdminJobListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 || resp.Jobs[0].ID != "job-beta-202" {
			t.Errorf("expected job-beta-202, got %+v", resp)
		}
	})

	t.Run("Filter by Owner ID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs?owner_id=owner-a", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)

		var resp AdminJobListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 2 {
			t.Errorf("expected 2 jobs for owner-a, got %d", resp.Total)
		}
	})

	t.Run("Filter by Courier ID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs?courier_id=emp-1", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)

		var resp AdminJobListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 2 {
			t.Errorf("expected 2 jobs for emp-1, got %d", resp.Total)
		}
	})

	t.Run("Filter by Recipient Phone Exact Match", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs?phone=%2B201022222222", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)

		var resp AdminJobListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 || resp.Jobs[0].ID != "job-alpha-101" {
			t.Errorf("expected job-alpha-101 by phone, got %+v", resp)
		}
	})

	t.Run("Filter by User Account Phone Exact Match", func(t *testing.T) {
		// +201033333333 belongs to user-2 in mock server
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs?phone=%2B201033333333", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)

		var resp AdminJobListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 || resp.Jobs[0].ID != "job-beta-202" {
			t.Errorf("expected job-beta-202 by user phone, got %+v", resp)
		}
	})

	t.Run("Filter by Status", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs?status=active", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)

		var resp AdminJobListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 || resp.Jobs[0].ID != "job-alpha-101" {
			t.Errorf("expected job-alpha-101 by active status, got %+v", resp)
		}
	})

	t.Run("Filter by Date Range", func(t *testing.T) {
		from := now.Add(-3 * 24 * time.Hour).Format(time.RFC3339)
		req := httptest.NewRequest(http.MethodGet, fmt.Sprintf("/admin/jobs?from=%s", from), nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListJobs(rec, req)

		var resp AdminJobListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 2 {
			t.Errorf("expected 2 jobs within date range, got %d", resp.Total)
		}
	})
}

func TestAdminJobs_DetailView(t *testing.T) {
	svc, mongoStore, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}
	ctx := context.Background()
	now := time.Now().UTC()

	agreedPrice := 120.0
	actualCash := 120.0
	jobID := "job-detail-test-1"

	job := &models.Job{
		ID:                 jobID,
		OwnerID:            "tenant-owner-1",
		UserID:             "cust-user-1",
		EmployeeID:         "courier-emp-1",
		ServiceID:          "service-deliv-1",
		Status:             models.JobStatusCompleted,
		Location:           models.Location{Latitude: 30.0444, Longitude: 31.2357, Address: "Tahrir Square, Cairo"},
		Destination:        models.Location{Latitude: 30.0131, Longitude: 31.2089, Address: "Pyramids St, Giza"},
		PaymentMethod:      "cod",
		SuggestedPrice:     100.0,
		AgreedPrice:        &agreedPrice,
		ActualCashAmount:   &actualCash,
		LockedEscrowAmount: 0,
		CustomerName:       "Customer VIP",
		Recipient: &models.JobRecipient{
			Name:  "Recipient Care",
			Phone: "+201011112222",
			Notes: "Ring doorbell twice",
		},
		PackageDetails: &models.PackageDetails{
			Size: models.PackageSizeLarge,
		},
		StatusHistory: []models.JobStatusHistoryEntry{
			{Status: models.JobStatusPending, At: now.Add(-1 * time.Hour), ActorRole: models.ActorRoleCustomer},
			{Status: models.JobStatusActive, At: now.Add(-45 * time.Minute), ActorRole: models.ActorRoleEmployee},
			{Status: models.JobStatusCompleted, At: now.Add(-15 * time.Minute), ActorRole: models.ActorRoleEmployee},
		},
		DistanceReview: &models.DistanceReview{
			ActualKm:  8.5,
			BookedKm:  12.0,
			FlaggedAt: now.Add(-15 * time.Minute),
			Source:    models.DistanceReviewSourceCompleteJob,
		},
		CreatedAt: now.Add(-1 * time.Hour),
		UpdatedAt: now,
	}
	_ = mongoStore.CreateJob(ctx, job)

	// Seed rating for this job
	_ = mongoStore.CreateRating(ctx, &models.Rating{
		ID:        "rating-1",
		JobID:     jobID,
		RatedBy:   "cust-user-1",
		RatedUser: "courier-emp-1",
		Stars:     5,
		Comment:   "Fast delivery, very polite!",
		CreatedAt: now,
	})

	t.Run("Successful Full V2 Detail View", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs/"+jobID, nil)
		req.SetPathValue("id", jobID)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminJobDetail(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp AdminJobDetailResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to decode detail view: %v", err)
		}

		if resp.ID != jobID {
			t.Errorf("expected job ID %s, got %s", jobID, resp.ID)
		}
		if resp.Status != models.JobStatusCompleted {
			t.Errorf("expected status completed, got %s", resp.Status)
		}
		if len(resp.StatusHistory) != 3 {
			t.Errorf("expected 3 status history entries, got %d", len(resp.StatusHistory))
		}
		if resp.Location.Address != "Tahrir Square, Cairo" {
			t.Errorf("expected pickup address text, got %q", resp.Location.Address)
		}
		if resp.Destination.Address != "Pyramids St, Giza" {
			t.Errorf("expected dropoff address text, got %q", resp.Destination.Address)
		}
		if resp.Recipient == nil || resp.Recipient.Phone != "+201011112222" {
			t.Errorf("expected unmasked recipient phone, got %+v", resp.Recipient)
		}
		if resp.CourierPhone != "+201099998888" {
			t.Errorf("expected courier phone from auth service, got %q", resp.CourierPhone)
		}
		if resp.CustomerPhone != "+201099998888" {
			t.Errorf("expected customer phone from auth service, got %q", resp.CustomerPhone)
		}
		if len(resp.Ratings) != 1 || resp.Ratings[0].Stars != 5 {
			t.Errorf("expected 1 rating with 5 stars, got %+v", resp.Ratings)
		}
		if len(resp.Notifications) != 1 || resp.Notifications[0].Type != "job_accepted" {
			t.Errorf("expected 1 notification item, got %+v", resp.Notifications)
		}
		if resp.ReconciliationFlags["distance_review"] == nil {
			t.Errorf("expected distance_review in reconciliation_flags")
		}
	})

	t.Run("Job Not Found", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/jobs/nonexistent-id", nil)
		req.SetPathValue("id", "nonexistent-id")
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminJobDetail(rec, req)

		if rec.Code != http.StatusNotFound {
			t.Errorf("expected 404 Not Found, got %d", rec.Code)
		}
	})
}
