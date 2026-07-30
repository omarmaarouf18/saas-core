package main

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestApproveKYCIntegration(t *testing.T) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("auth_platform_kyc_test_%d", time.Now().UnixNano())
	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName, nil)
	if err != nil {
		t.Skipf("Skipping integration tests: MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = mongoStore.DropDatabase(context.Background())
		_ = mongoStore.Close(context.Background())
	}()

	ownerEmail := "owner_kyc_test@example.com"
	userID := "user-owner-123"

	// 1. Seed owner user with pending KYC status
	ownerUser := &models.User{
		ID:          userID,
		Email:       ownerEmail,
		Role:        models.RoleOwner,
		KYCStatus:   models.KYCPendingApproval,
		IsActive:    true,
		IsConfirmed: true,
		CreatedAt:   time.Now(),
	}

	if err := mongoStore.CreateUser(ctx, ownerUser); err != nil {
		t.Fatalf("failed to seed owner user: %v", err)
	}

	// 2. Fetch and assert initial state
	dbUser := mongoStore.GetByEmail(ctx, ownerEmail)
	if dbUser == nil {
		t.Fatalf("failed to retrieve owner by email")
	}
	if dbUser.Role != models.RoleOwner {
		t.Errorf("expected role owner, got %s", dbUser.Role)
	}
	if dbUser.KYCStatus != models.KYCPendingApproval {
		t.Errorf("expected KYCStatus pending, got %s", dbUser.KYCStatus)
	}

	// 3. Simulate "approve" action using UpdateUser
	approvedStatus := models.KYCApproved
	updateApprove := bson.M{"$set": bson.M{
		"kyc_status":       approvedStatus,
		"rejection_reason": "",
		"reviewed_at":      time.Now(),
		"reviewer_id":      "super_admin_cli",
	}}

	if err := mongoStore.UpdateUser(ctx, userID, updateApprove); err != nil {
		t.Fatalf("failed to update user to approved: %v", err)
	}

	dbUserApproved := mongoStore.GetByEmail(ctx, ownerEmail)
	if dbUserApproved.KYCStatus != models.KYCApproved {
		t.Errorf("expected KYCStatus approved, got %s", dbUserApproved.KYCStatus)
	}
	if dbUserApproved.RejectionReason != "" {
		t.Errorf("expected empty rejection reason, got %s", dbUserApproved.RejectionReason)
	}

	// Reset to pending for reject test
	resetPending := bson.M{"$set": bson.M{
		"kyc_status": models.KYCPendingApproval,
	}}
	if err := mongoStore.UpdateUser(ctx, userID, resetPending); err != nil {
		t.Fatalf("failed to reset user to pending: %v", err)
	}

	// 4. Simulate "reject" action
	rejectedStatus := models.KYCRejected
	rejectReason := "Documents are blurry"
	updateReject := bson.M{"$set": bson.M{
		"kyc_status":       rejectedStatus,
		"rejection_reason": rejectReason,
		"reviewed_at":      time.Now(),
		"reviewer_id":      "super_admin_cli",
	}}

	if err := mongoStore.UpdateUser(ctx, userID, updateReject); err != nil {
		t.Fatalf("failed to update user to rejected: %v", err)
	}

	dbUserRejected := mongoStore.GetByEmail(ctx, ownerEmail)
	if dbUserRejected.KYCStatus != models.KYCRejected {
		t.Errorf("expected KYCStatus rejected, got %s", dbUserRejected.KYCStatus)
	}
	if dbUserRejected.RejectionReason != rejectReason {
		t.Errorf("expected rejection reason %q, got %q", rejectReason, dbUserRejected.RejectionReason)
	}
}
