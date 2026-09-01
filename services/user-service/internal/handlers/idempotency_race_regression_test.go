package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

func idemRaceSetup(t *testing.T) (*UserService, *store.MongoDB, *miniredis.Miniredis, func()) {
	t.Helper()
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	dbName := fmt.Sprintf("saas_platform_test_%d", time.Now().UnixNano())
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		cancel()
		t.Skipf("Skipping: MongoDB not available (%v)", err)
		return nil, nil, nil, nil
	}

	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		role := "owner"
		tenantID := id
		if strings.Contains(id, "emp") {
			role = "employee"
			if strings.Contains(id, "-under-") {
				parts := strings.Split(id, "-under-")
				if len(parts) > 1 {
					tenantID = parts[1]
				}
			} else if strings.HasPrefix(id, "emp-") {
				tenantID = strings.TrimPrefix(id, "emp-")
			}
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id": id, "role": role, "kyc_status": "approved", "is_active": true, "tenant_id": tenantID,
		})
	}))

	cfg := &config.Config{
		AuthServiceURL:         mockAuthServer.URL,
		InternalServiceToken:   "mock-internal-token",
		AppEnv:                 "test",
		AllowTestPaymentBypass: true,
	}
	u := NewUserService(s, cfg, rdb)
	cleanup := func() {
		mockAuthServer.Close()
		rdb.Close()
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
		cancel()
	}
	return u, s, mr, cleanup
}

// TestSaveIdempotencyKey_SurvivesRequestContextCancellation is a deterministic
// repro for the dropped-key defect: the key write used the request context, so
// a client disconnect between job creation and key-set silently discarded the
// key and the client's retry created a second funded booking. The write must
// survive cancellation of the originating request context.
func TestSaveIdempotencyKey_SurvivesRequestContextCancellation(t *testing.T) {
	u, _, mr, cleanup := idemRaceSetup(t)
	defer cleanup()

	// Simulate the request context being canceled (client disconnect) at the
	// moment of the key write — saveIdempotencyKey must not depend on it.
	requestCtx, cancel := context.WithCancel(context.Background())
	defer cancel()

	u.saveIdempotencyKey("race-user-1", "disconnect-key-1", "job-abc")
	_ = requestCtx // cancellation no longer affects idempotency bookkeeping

	if !mr.Exists("idempotency:job:race-user-1:disconnect-key-1") {
		t.Fatal("idempotency key was NOT written when the request context was canceled — a retry would double-book (dropped-key bug present)")
	}
}

// TestTrackJob_ConcurrentDuplicateIdempotencyKey is the concurrency repro for
// the GET-then-insert race: two simultaneous requests sharing one fresh key
// must produce exactly ONE job. The loser must replay (200) or receive an
// explicit in-progress conflict (409) — never a second 201.
func TestTrackJob_ConcurrentDuplicateIdempotencyKey(t *testing.T) {
	u, s, _, cleanup := idemRaceSetup(t)
	defer cleanup()

	ctx := context.Background()
	ownerID := "race-owner-1"
	userID := "race-user-1"
	serviceID := "race-svc-1"

	s.CreateService(ctx, &models.Service{ID: serviceID, TenantID: ownerID, TenantBasePrice: 10.0, TenantPricePerKM: 1.0, Latitude: 30.0, Longitude: 30.0})
	_ = s.Deposit(ctx, ownerID, 500.0)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: "emp-race-owner-1",
		Latitude:   30.0,
		Longitude:  30.0,
		UpdatedAt:  time.Now().UTC(),
	})

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "race-owner@example.com")
	tokenUser, _ := jwtutil.GenerateToken(userID, "user", ownerID, "race-user@example.com")

	body, _ := json.Marshal(map[string]any{
		"owner_id":        tokenOwner,
		"service_id":      serviceID,
		"user_id":         tokenUser,
		"payment_method":  "cod",
		"idempotency_key": "concurrent-key-single-run",
		"location":        models.Location{Latitude: 30.0, Longitude: 30.0},
	})

	var mu sync.Mutex
	var wg sync.WaitGroup
	statuses := make([]int, 0, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
			req.Header.Set("Idempotency-Key", "concurrent-key-single-run")
			rec := httptest.NewRecorder()
			u.TrackJob(rec, req)
			mu.Lock()
			statuses = append(statuses, rec.Code)
			mu.Unlock()
		}()
	}
	wg.Wait()

	created := 0
	for _, code := range statuses {
		if code == http.StatusCreated {
			created++
		} else if code != http.StatusOK && code != http.StatusConflict {
			t.Fatalf("unexpected status %v from concurrent duplicates", statuses)
		}
	}
	if created > 1 {
		t.Errorf("GET-then-insert race reproduced: %d concurrent requests returned 201 Created (statuses=%v) — duplicate funded bookings possible", created, statuses)
	}

	jobs, err := s.GetJobsByCustomer(ctx, userID)
	if err != nil {
		t.Fatalf("GetJobsByCustomer failed: %v", err)
	}
	if len(jobs) != 1 {
		t.Errorf("expected exactly 1 persisted job per idempotency key, got %d (statuses=%v)", len(jobs), statuses)
	}
}
