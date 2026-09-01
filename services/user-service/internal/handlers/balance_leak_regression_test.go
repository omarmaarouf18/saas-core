package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// Cross-tenant financial disclosure: escrow-lock failures previously echoed
// the raw store error ("insufficient withdrawable balance: have %.2f, need
// %.2f") to the CLIENT via a "warning" field, exposing the tenant owner's
// exact wallet balance to customers/employees of unrelated tenants.

func TestTrackJob_EscrowFailureWarningDoesNotLeakOwnerBalance(t *testing.T) {
	u, s, _, cleanup := idemRaceSetup(t)
	defer cleanup()

	ctx := context.Background()
	ownerID := "leak-owner" // deliberately funded with ZERO balance
	svcID := "leak-svc"
	s.CreateService(ctx, &models.Service{ID: svcID, TenantID: ownerID, TenantBasePrice: 40.0, TenantPricePerKM: 1.0, Latitude: 30.0, Longitude: 30.0})

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "leak-owner@example.com")
	tokenUser, _ := jwtutil.GenerateToken("leak-cust", "user", ownerID, "leak-cust@example.com")

	body, _ := json.Marshal(map[string]any{
		"owner_id":       tokenOwner,
		"service_id":     svcID,
		"user_id":        tokenUser,
		"payment_method": "wallet",
		"location":       models.Location{Latitude: 30.05, Longitude: 30.05},
	})
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 with escrow-lock-failure warning, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	for _, secret := range []string{"withdrawable balance", "insufficient withdrawable"} {
		if bytes.Contains(rec.Body.Bytes(), []byte(secret)) {
			t.Errorf("response leaks owner balance detail %q in body: %s", secret, rec.Body.String())
		}
	}
}

func TestRespondPrice_EscrowFailureWarningDoesNotLeakOwnerBalance(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	s, err := store.NewMongoDB(ctx, mongoURI,
		fmt.Sprintf("saas_platform_test_%d", time.Now().UnixNano()))
	if err != nil {
		t.Skipf("Skipping: MongoDB not available (%v)", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	ownerID := "leak-owner-2" // zero balance
	empID := "leak-emp"
	custID := "leak-cust-2"
	svcID := "leak-svc-2"

	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		role := "user"
		switch id {
		case ownerID:
			role = "owner"
		case empID:
			role = "employee"
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id": id, "role": role, "kyc_status": "approved", "is_active": true, "tenant_id": ownerID,
		})
	}))
	defer mockAuth.Close()

	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	cfg := &config.Config{
		AuthServiceURL:         mockAuth.URL,
		InternalServiceToken:   "mock-internal-token",
		AppEnv:                 "test",
		AllowTestPaymentBypass: true,
	}
	u := NewUserService(s, cfg, rdb)

	s.CreateService(ctx, &models.Service{ID: svcID, Category: "transport", TenantID: ownerID,
		TenantBasePrice: 50.0, TenantPricePerKM: 1.0, Latitude: 30.0, Longitude: 30.0})

	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "leak-emp@example.com")
	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "leak-cust2@example.com")
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empID,
		Latitude:   30.0,
		Longitude:  30.0,
		UpdatedAt:  time.Now().UTC(),
	})

	// Customer books transport job WITH pre-assigned employee -> awaiting_price_response.
	bookBody, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust,
		"employee_id":    tokenEmp,
		"payment_method": "wallet",
		"location":       models.Location{Latitude: 30.01, Longitude: 30.01},
	})
	reqBook := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(bookBody))
	recBook := httptest.NewRecorder()
	u.TrackJob(recBook, reqBook)
	if recBook.Code != http.StatusCreated {
		t.Fatalf("booking failed: %d %s", recBook.Code, recBook.Body.String())
	}
	var booked map[string]any
	_ = json.Unmarshal(recBook.Body.Bytes(), &booked)
	jobObj, _ := booked["job"].(map[string]any)
	jobID, _ := jobObj["id"].(string)

	// Employee proposes a counter price.
	propBody, _ := json.Marshal(map[string]any{"job_id": jobID, "proposed_price": 45.0, "requester_token": tokenEmp})
	reqProp := httptest.NewRequest("POST", "/users/jobs/propose-price", bytes.NewReader(propBody))
	recProp := httptest.NewRecorder()
	u.ProposePrice(recProp, reqProp)
	if recProp.Code != http.StatusOK && recProp.Code != http.StatusCreated {
		t.Fatalf("propose failed: %d %s", recProp.Code, recProp.Body.String())
	}

	// Customer accepts; escrow lock must fail (owner has zero balance).
	accBody, _ := json.Marshal(map[string]any{"job_id": jobID, "decision": "accept", "requester_token": tokenCust})
	reqAcc := httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewReader(accBody))
	recAcc := httptest.NewRecorder()
	u.RespondPrice(recAcc, reqAcc)

	if recAcc.Code == http.StatusOK {
		t.Fatalf("expected non-200 due to insufficient funds, got 200: %s", recAcc.Body.String())
	}
	for _, secret := range []string{"withdrawable balance", "insufficient withdrawable"} {
		if bytes.Contains(recAcc.Body.Bytes(), []byte(secret)) {
			t.Errorf("RespondPrice leaks owner balance detail %q in body: %s", secret, recAcc.Body.String())
		}
	}
}
