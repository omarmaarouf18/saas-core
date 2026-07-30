package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

func TestOnboardReviewerIntegration(t *testing.T) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("auth_platform_onboard_test_%d", time.Now().UnixNano())
	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName, nil)
	if err != nil {
		t.Skipf("Skipping integration tests: MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = mongoStore.Close(context.Background())
	}()

	reviewerID := "reviewer_test_duplicate"

	// 1. Seed a reviewer
	rev := &models.Reviewer{
		ID:    reviewerID,
		Name:  "Test Reviewer",
		Token: "test-token-456",
	}
	if err := mongoStore.AddReviewer(ctx, rev); err != nil {
		t.Fatalf("failed to add reviewer: %v", err)
	}

	// 2. Try to query it and verify it exists
	existingRev, err := mongoStore.GetReviewerByID(ctx, reviewerID)
	if err != nil {
		t.Fatalf("failed to fetch seeded reviewer: %v", err)
	}
	if existingRev.ID != reviewerID {
		t.Errorf("expected reviewer ID %s, got %s", reviewerID, existingRev.ID)
	}

	// 3. Check sparse unique token lookup
	revByToken, err := mongoStore.GetReviewerByToken(ctx, "test-token-456")
	if err != nil {
		t.Fatalf("failed to fetch reviewer by token: %v", err)
	}
	if revByToken.ID != reviewerID {
		t.Errorf("expected reviewer ID %s, got %s", reviewerID, revByToken.ID)
	}

	// 4. Test missing reviewer returns ErrNoDocuments
	_, err3 := mongoStore.GetReviewerByID(ctx, "non_existent_reviewer")
	if !errors.Is(err3, mongo.ErrNoDocuments) {
		t.Errorf("expected ErrNoDocuments for non-existent reviewer, got: %v", err3)
	}
}
