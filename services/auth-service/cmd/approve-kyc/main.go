// Package main implements a standalone CLI tool to approve or reject owner KYC documents.
// Usage:
//
//	MONGO_URI=mongodb://localhost:27017 go run ./services/auth-service/cmd/approve-kyc --email=owner@example.com --action=approve
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"go.mongodb.org/mongo-driver/v2/bson"
)

func main() {
	var email string
	var action string
	var reason string
	var yesFlag bool

	flag.StringVar(&email, "email", "", "The owner user's registration email (required)")
	flag.StringVar(&action, "action", "", "The action to perform: 'approve' or 'reject' (required)")
	flag.StringVar(&reason, "reason", "", "The reason for rejection (required if action is 'reject')")
	flag.BoolVar(&yesFlag, "yes", false, "Confirm and bypass the interactive prompt")
	flag.Parse()

	if email == "" {
		flag.Usage()
		log.Fatal("Error: --email flag is required")
	}

	action = strings.ToLower(strings.TrimSpace(action))
	if action != "approve" && action != "reject" {
		flag.Usage()
		log.Fatal("Error: --action flag must be 'approve' or 'reject'")
	}

	if action == "reject" && strings.TrimSpace(reason) == "" {
		flag.Usage()
		log.Fatal("Error: --reason flag is required when action is 'reject'")
	}

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	dbName := os.Getenv("AUTH_MONGO_DATABASE")
	if dbName == "" {
		dbName = os.Getenv("MONGO_INITDB_DATABASE")
	}
	if dbName == "" {
		dbName = "auth_db"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName, nil)
	if err != nil {
		log.Fatalf("Error: Failed to connect to MongoDB: %v", err)
	}
	defer func() {
		_ = mongoStore.Close(context.Background())
	}()

	// 1. Look up user by email
	user := mongoStore.GetByEmail(ctx, email)
	if user == nil {
		log.Fatalf("Error: User with email %q not found", email)
	}

	// 2. Verify role is owner
	if user.Role != models.RoleOwner {
		// #nosec G706 //nolint:gosec -- admin CLI utility inputs, not untrusted web inputs, log injection is not a concern
		log.Fatalf("Error: User %q is not an owner (role: %s). KYC is only applicable to owners.", email, user.Role)
	}

	// 3. Verify current KYC status is pending_super_admin_approval
	if user.KYCStatus != models.KYCPendingApproval {
		// #nosec G706 //nolint:gosec -- admin CLI utility inputs, not untrusted web inputs, log injection is not a concern
		log.Fatalf("Error: Owner %q has KYC status %q, but exactly %q is required.", email, user.KYCStatus, models.KYCPendingApproval)
	}

	// Print current state and target state
	fmt.Println("Current KYC Status State:")
	fmt.Printf("  Email:          %s\n", user.Email)
	fmt.Printf("  Role:           %s\n", user.Role)
	fmt.Printf("  Current KYC:    %s\n", user.KYCStatus)
	fmt.Println("Target KYC Action:")
	fmt.Printf("  Action:         %s\n", action)
	if action == "reject" {
		fmt.Printf("  Reason:         %s\n", reason)
	}
	fmt.Println()

	// 4. Interactive confirmation if --yes is not set
	if !yesFlag {
		fmt.Printf("Are you sure you want to %s KYC for owner %q? (y/N): ", action, email)
		var response string
		_, _ = fmt.Scanln(&response)
		response = strings.ToLower(strings.TrimSpace(response))
		if response != "y" && response != "yes" {
			fmt.Println("Aborted.")
			return
		}
	}

	// 5. Update KYC status
	var newStatus models.KYCStatus
	var setReason string
	if action == "approve" {
		newStatus = models.KYCApproved
	} else {
		newStatus = models.KYCRejected
		setReason = reason
	}

	update := bson.M{"$set": bson.M{
		"kyc_status":       newStatus,
		"rejection_reason": setReason,
		"reviewed_at":      time.Now(),
		"reviewer_id":      "super_admin_cli",
	}}

	if err := mongoStore.UpdateUser(ctx, user.ID, update); err != nil {
		log.Fatalf("Error: Failed to update KYC status: %v", err)
	}

	// 6. Print success and final status
	fmt.Printf("\nSuccessfully updated KYC status!\n")
	fmt.Println("----------------------------------------------------------------------")
	fmt.Printf("Owner Email:      %s\n", email)
	fmt.Printf("New KYC Status:   %s\n", newStatus)
	if newStatus == models.KYCRejected {
		fmt.Printf("Rejection Reason: %s\n", setReason)
	}
	fmt.Println("----------------------------------------------------------------------")
}
