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
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// TestCreateService_StoreFailure_Returns500: BE-ERR — CreateService used to
// answer 201 "service created" even when the insert failed (the store only
// logged it). The insert is made to fail with a real collection validator.
func TestCreateService_StoreFailure_Returns500(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	dbName := fmt.Sprintf("saas_user_be_err_handler_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping: MongoDB not available (%v)", err)
	}
	raw, err := mongo.Connect(options.Client().ApplyURI(mongoURI))
	if err != nil {
		t.Fatalf("raw connect: %v", err)
	}
	t.Cleanup(func() {
		_ = s.DropDatabase(context.Background())
		_ = s.Close(context.Background())
		_ = raw.Disconnect(context.Background())
	})

	ownerID := "be-err-owner"
	if err := s.UpsertSubscription(ctx, &models.Subscription{TenantID: ownerID, Tier: models.PlanPaid, ExpiresAt: time.Now().Add(24 * time.Hour)}); err != nil {
		t.Fatalf("seed subscription: %v", err)
	}
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"id": ownerID, "role": "owner", "kyc_status": "approved", "is_active": true, "tenant_id": ownerID})
	}))
	t.Cleanup(auth.Close)
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	u := NewUserService(s, &config.Config{AuthServiceURL: auth.URL, InternalServiceToken: "mock-internal-token", AppEnv: "test"}, rdb)

	token, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "be-err@example.com")
	post := func() *httptest.ResponseRecorder {
		body, _ := json.Marshal(map[string]any{
			"owner_id": token, "name": "BE-ERR Service", "category": "delivery",
			"tenant_base_price": 10.0, "tenant_price_per_km": 1.0, "latitude": 30.0, "longitude": 31.0,
		})
		rec := httptest.NewRecorder()
		u.CreateService(rec, httptest.NewRequest("POST", "/users/services", bytes.NewReader(body)))
		return rec
	}

	if rec := post(); rec.Code != http.StatusCreated {
		t.Fatalf("control: expected 201 before the failure is injected, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	cmd := bson.D{{Key: "collMod", Value: "services"}, {Key: "validator", Value: bson.M{"__be_err_never": bson.M{"$exists": true}}}}
	if err := raw.Database(dbName).RunCommand(ctx, cmd).Err(); err != nil {
		t.Fatalf("collMod: %v", err)
	}
	rec := post()
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 when the insert fails, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Code string `json:"code"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Code != "internal_error" {
		t.Errorf("expected code internal_error, got %q", resp.Code)
	}
}
