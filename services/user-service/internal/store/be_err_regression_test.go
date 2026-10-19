package store

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"

	"github.com/project/user-service/internal/models"
)

// BE-ERR: store writes whose errors were only logged. Failures are injected
// with a real MongoDB collection validator, not a mock.

// rejectAllValidator matches no document, so every insert into (or update
// of) a collection carrying it fails with DocumentValidationFailure.
var rejectAllValidator = bson.M{"__be_err_never": bson.M{"$exists": true}}

func beErrMongoURI() string {
	if uri := os.Getenv("MONGO_URI"); uri != "" {
		return uri
	}
	return "mongodb://root:devpassword123@localhost:27017/?authSource=admin"
}

// beErrRawDB connects a plain client to a fresh database name, or skips.
func beErrRawDB(t *testing.T) (*mongo.Database, string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	client, err := mongo.Connect(options.Client().ApplyURI(beErrMongoURI()))
	if err != nil {
		t.Skipf("Skipping BE-ERR store tests: %v", err)
	}
	if err := client.Ping(ctx, nil); err != nil {
		_ = client.Disconnect(context.Background())
		t.Skipf("Skipping BE-ERR store tests: MongoDB unreachable (%v)", err)
	}
	dbName := fmt.Sprintf("saas_user_be_err_test_%d", time.Now().UnixNano())
	db := client.Database(dbName)
	t.Cleanup(func() {
		_ = db.Drop(context.Background())
		_ = client.Disconnect(context.Background())
	})
	return db, dbName
}

func beErrStore(t *testing.T) *MongoDB {
	t.Helper()
	_, dbName := beErrRawDB(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	s, err := NewMongoDB(ctx, beErrMongoURI(), dbName)
	if err != nil {
		t.Fatalf("NewMongoDB: %v", err)
	}
	t.Cleanup(func() { _ = s.Close(context.Background()) })
	return s
}

func setValidator(t *testing.T, db *mongo.Database, coll string, validator bson.M) {
	t.Helper()
	cmd := bson.D{{Key: "collMod", Value: coll}, {Key: "validator", Value: validator}, {Key: "validationLevel", Value: "strict"}}
	if err := db.RunCommand(context.Background(), cmd).Err(); err != nil {
		t.Fatalf("collMod %s: %v", coll, err)
	}
}

func createRejectingCollection(t *testing.T, db *mongo.Database, coll string) {
	t.Helper()
	opts := options.CreateCollection().SetValidator(rejectAllValidator)
	if err := db.CreateCollection(context.Background(), coll, opts); err != nil {
		t.Fatalf("create %s: %v", coll, err)
	}
}

func TestCreateService_InsertFailure_ReturnsError(t *testing.T) {
	s := beErrStore(t)
	ctx := context.Background()
	svc := &models.Service{ID: "be-err-svc", TenantID: "be-err-owner", Name: "S", Category: "delivery", Latitude: 30, Longitude: 31}

	if err := s.CreateService(ctx, svc); err != nil {
		t.Fatalf("first CreateService: %v", err)
	}
	dup := *svc
	if err := s.CreateService(ctx, &dup); !errors.Is(err, ErrServiceExists) {
		t.Errorf("expected ErrServiceExists for a duplicate ID, got %v", err)
	}

	setValidator(t, s.db, "services", rejectAllValidator)
	other := &models.Service{ID: "be-err-svc-2", TenantID: "be-err-owner", Name: "S2", Category: "delivery", Latitude: 30, Longitude: 31}
	err := s.CreateService(ctx, other)
	if err == nil {
		t.Fatalf("expected an error when the insert is rejected, got nil")
	}
	if errors.Is(err, ErrServiceExists) {
		t.Errorf("a validation failure must not be reported as a duplicate: %v", err)
	}
}

func TestNewMongoDB_PlatformConfigSeedFailure_ReturnsError(t *testing.T) {
	db, dbName := beErrRawDB(t)
	createRejectingCollection(t, db, "platform_config")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	s, err := NewMongoDB(ctx, beErrMongoURI(), dbName)
	if err == nil {
		_ = s.Close(context.Background())
		t.Fatalf("expected NewMongoDB to fail when the platform config cannot be seeded, got nil")
	}
	if !strings.Contains(err.Error(), "platform config") {
		t.Errorf("expected a platform config error, got %v", err)
	}
}

func TestNewMongoDB_PlatformWalletSeedFailure_ReturnsError(t *testing.T) {
	db, dbName := beErrRawDB(t)
	createRejectingCollection(t, db, "wallets")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	s, err := NewMongoDB(ctx, beErrMongoURI(), dbName)
	if err == nil {
		_ = s.Close(context.Background())
		t.Fatalf("expected NewMongoDB to fail when the platform wallet cannot be seeded, got nil")
	}
}

func TestNewMongoDB_DemoSeedFailure_ReturnsError(t *testing.T) {
	t.Setenv("SEED_DEMO_DATA", "true")
	db, dbName := beErrRawDB(t)
	createRejectingCollection(t, db, "services")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	s, err := NewMongoDB(ctx, beErrMongoURI(), dbName)
	if err == nil {
		_ = s.Close(context.Background())
		t.Fatalf("expected NewMongoDB to fail when demo services cannot be seeded, got nil")
	}
}

func TestNewMongoDB_SeedIsIdempotent(t *testing.T) {
	t.Setenv("SEED_DEMO_DATA", "true")
	_, dbName := beErrRawDB(t)
	for i := 0; i < 2; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		s, err := NewMongoDB(ctx, beErrMongoURI(), dbName)
		cancel()
		if err != nil {
			t.Fatalf("NewMongoDB run %d: %v", i+1, err)
		}
		_ = s.Close(context.Background())
	}
}

// TestTryAcquireCourierLock_RetryError_IsReturned: the stale-lock self-heal
// used to swallow the retry's store error and report "courier busy"
// (false, nil).
func TestTryAcquireCourierLock_RetryError_IsReturned(t *testing.T) {
	s := beErrStore(t)
	ctx := context.Background()
	if _, err := s.employeeLocations.InsertOne(ctx, bson.M{
		"tenant_id": "be-err-t", "employee_id": "be-err-e", "active_job_id": "stale-job-gone",
	}); err != nil {
		t.Fatalf("seed location: %v", err)
	}
	// Releasing the stale lock ("" ) is allowed; taking the new job is not.
	setValidator(t, s.db, "employee_locations", bson.M{"active_job_id": bson.M{"$in": []string{"", "stale-job-gone"}}})

	ok, err := s.TryAcquireCourierLock(ctx, "be-err-t", "be-err-e", "new-job")
	if err == nil {
		t.Fatalf("expected the retry's store error to be returned, got ok=%v err=<nil>", ok)
	}
	if ok {
		t.Errorf("expected ok=false on error")
	}
}

// TestAdminActivateSubscription_InsertError_KeepsCause: a failed insert used
// to be reported as "not found or was concurrently modified" (mapped to 409).
func TestAdminActivateSubscription_InsertError_KeepsCause(t *testing.T) {
	s := beErrStore(t)
	setValidator(t, s.db, "subscriptions", rejectAllValidator)

	_, err := s.AdminActivateSubscription(context.Background(), "be-err-sub-tenant", "", 30, "reviewer-1")
	if err == nil {
		t.Fatalf("expected an error, got nil")
	}
	if strings.Contains(err.Error(), "concurrently modified") {
		t.Errorf("insert failure must not be reported as a conflict: %v", err)
	}
	var we mongo.WriteException
	if !errors.As(err, &we) {
		t.Errorf("expected the Mongo write error to be wrapped, got %v", err)
	}
}
