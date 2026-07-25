package store

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/otpcrypto"
	"go.mongodb.org/mongo-driver/v2/bson"
)

func setupTestStore(t *testing.T) (*MongoDB, func()) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_auth_store_test_%d", time.Now().UnixNano())
	cipher, err := otpcrypto.NewCipher("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "test")
	if err != nil {
		t.Fatalf("failed to create cipher: %v", err)
	}

	s, err := NewMongoDB(ctx, mongoURI, dbName, cipher)
	if err != nil {
		t.Skipf("Skipping MongoDB store tests: MongoDB unreachable at %s (%v)", mongoURI, err)
		return nil, nil
	}

	cleanup := func() {
		cleanupCtx, cCancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cCancel()
		_ = s.DropDatabase(cleanupCtx)
		_ = s.Close(cleanupCtx)
	}

	return s, cleanup
}

func TestMongoDB_InvalidURI(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	// Invalid URI / unreachable port
	_, err := NewMongoDB(ctx, "mongodb://127.0.0.1:59999", "testdb", nil)
	if err == nil {
		t.Errorf("Expected error connecting to unreachable MongoDB URI, got nil")
	}
}

func TestMongoDB_UserCRUD(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. CreateUser
	user := &models.User{
		ID:          "usr-1",
		Email:       "testcrud@example.com",
		Username:    "testcrud",
		Password:    "hashedpass",
		Role:        models.RoleOwner,
		IsActive:    true,
		IsConfirmed: true,
		KYCStatus:   models.KYCPendingApproval,
		CreatedAt:   time.Now(),
	}

	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("CreateUser failed: %v", err)
	}

	// 2. CreateUser duplicate email -> unique index error
	dupUser := &models.User{
		ID:       "usr-2",
		Email:    "testcrud@example.com",
		Username: "dupuser",
		Role:     models.RoleUser,
	}
	if err := s.CreateUser(ctx, dupUser); err == nil {
		t.Errorf("Expected error inserting user with duplicate email, got nil")
	}

	// 3. GetByEmail & GetByID
	byEmail := s.GetByEmail(ctx, "testcrud@example.com")
	if byEmail == nil || byEmail.ID != "usr-1" {
		t.Fatalf("GetByEmail returned unexpected user: %v", byEmail)
	}

	byID := s.GetByID(ctx, "usr-1")
	if byID == nil || byID.Email != "testcrud@example.com" {
		t.Fatalf("GetByID returned unexpected user: %v", byID)
	}

	// Non-existent lookups
	if s.GetByEmail(ctx, "nonexistent@example.com") != nil {
		t.Errorf("Expected nil for non-existent email")
	}
	if s.GetByID(ctx, "nonexistent-id") != nil {
		t.Errorf("Expected nil for non-existent ID")
	}

	// 4. UpdateKYCStatus & UpdateUser
	if err := s.UpdateKYCStatus(ctx, "usr-1", models.KYCApproved); err != nil {
		t.Fatalf("UpdateKYCStatus failed: %v", err)
	}

	if err := s.UpdateUser(ctx, "usr-1", bson.M{"$set": bson.M{"phone": "+123456789"}}); err != nil {
		t.Fatalf("UpdateUser failed: %v", err)
	}

	updated := s.GetByID(ctx, "usr-1")
	if updated.KYCStatus != models.KYCApproved || updated.Phone != "+123456789" {
		t.Errorf("Update verification failed: status=%s, phone=%s", updated.KYCStatus, updated.Phone)
	}

	// 5. GetPendingKYBKYE
	pendingUser := &models.User{
		ID:        "usr-pending",
		Email:     "pending@example.com",
		Username:  "pendinguser",
		KYCStatus: models.KYCPendingApproval,
	}
	_ = s.CreateUser(ctx, pendingUser)

	pendingList, err := s.GetPendingKYBKYE(ctx)
	if err != nil {
		t.Fatalf("GetPendingKYBKYE failed: %v", err)
	}
	if len(pendingList) == 0 {
		t.Errorf("Expected pending users in GetPendingKYBKYE list")
	}

	// 6. DeleteUser
	if err := s.DeleteUser(ctx, "usr-1"); err != nil {
		t.Fatalf("DeleteUser failed: %v", err)
	}
	if s.GetByID(ctx, "usr-1") != nil {
		t.Errorf("Expected user usr-1 to be deleted")
	}
}

func TestMongoDB_OTPFlows(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:          "otp-usr-1",
		Email:       "otp@example.com",
		Username:    "otpuser",
		Role:        models.RoleUser,
		IsActive:    true,
		IsConfirmed: true,
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	// 1. SetOTP
	if err := s.SetOTP(ctx, "otp@example.com", "654321"); err != nil {
		t.Fatalf("SetOTP failed: %v", err)
	}

	// 2. VerifyOTP wrong code -> returns error
	err := s.VerifyOTP(ctx, "otp@example.com", "999999")
	if err == nil {
		t.Errorf("Expected VerifyOTP with wrong code to return error, got nil")
	}

	// 3. VerifyOTP correct code -> returns nil
	err = s.VerifyOTP(ctx, "otp@example.com", "654321")
	if err != nil {
		t.Errorf("Expected VerifyOTP with correct code to succeed, got %v", err)
	}
}

func TestMongoDB_EmployeesAndAudit(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "owner-store-1"
	emp1 := &models.User{
		ID:       "emp-store-1",
		Email:    "emp1@example.com",
		OwnerID:  ownerID,
		Role:     models.RoleEmployee,
		IsActive: true,
	}
	_ = s.CreateUser(ctx, emp1)

	// 1. GetEmployeesByOwner
	emps := s.GetEmployeesByOwner(ctx, ownerID)
	if len(emps) != 1 || emps[0].ID != "emp-store-1" {
		t.Errorf("GetEmployeesByOwner returned unexpected employees: %v", emps)
	}

	// 2. ToggleEmployeeActive
	if err := s.ToggleEmployeeActive(ctx, "emp1@example.com", ownerID, false); err != nil {
		t.Fatalf("ToggleEmployeeActive failed: %v", err)
	}
	updatedEmp := s.GetByID(ctx, "emp-store-1")
	if updatedEmp.IsActive {
		t.Errorf("Expected employee to be deactivated")
	}

	// 3. Audit Log
	entry := models.AuditEntry{
		ID:         "audit-1",
		EmployeeID: "emp-store-1",
		TenantID:   ownerID,
		Action:     "check_in",
		Timestamp:  time.Now(),
		ClientIP:   "127.0.0.1",
	}
	s.AppendAudit(ctx, entry)

	logs := s.GetAuditLog(ctx, ownerID)
	if len(logs) != 1 || logs[0].Action != "check_in" {
		t.Errorf("GetAuditLog returned unexpected logs: %v", logs)
	}

	count := s.AuditCount(ctx)
	if count != 1 {
		t.Errorf("Expected AuditCount 1, got %d", count)
	}
}

func TestMongoDB_Reviewers(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. AddReviewer
	rev := &models.Reviewer{
		ID:    "rev-1",
		Token: "secret-reviewer-token-123",
		Name:  "Omar Reviewer",
	}
	if err := s.AddReviewer(ctx, rev); err != nil {
		t.Fatalf("AddReviewer failed: %v", err)
	}

	// 2. GetReviewerByID
	gotID, err := s.GetReviewerByID(ctx, "rev-1")
	if err != nil || gotID.Name != "Omar Reviewer" {
		t.Errorf("GetReviewerByID returned unexpected reviewer: %v, err=%v", gotID, err)
	}

	// 3. GetReviewerByToken
	gotTok, err := s.GetReviewerByToken(ctx, "secret-reviewer-token-123")
	if err != nil || gotTok.ID != "rev-1" {
		t.Errorf("GetReviewerByToken returned unexpected reviewer: %v, err=%v", gotTok, err)
	}

	// Non-existent
	_, err = s.GetReviewerByToken(ctx, "non-existent-token")
	if err == nil {
		t.Errorf("Expected error for non-existent reviewer token")
	}
}

func TestMongoDB_OTPCleanup(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx, cancel := context.WithCancel(context.Background())
	// Cancel context immediately so ticker loop exits gracefully
	cancel()
	s.StartOTPCleanup(ctx, 10*time.Millisecond)
	time.Sleep(20 * time.Millisecond)
}
