// Package main implements a standalone CLI tool to onboard KYB/KYE reviewers.
// Usage:
//
//	MONGO_URI=mongodb://localhost:27017 go run ./services/auth-service/cmd/onboard-reviewer --id=reviewer_omar --name="Omar Maarouf"
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

func main() {
	var reviewerID string
	var reviewerName string
	var yesFlag bool

	flag.StringVar(&reviewerID, "id", "", "The unique identifier of the reviewer (required)")
	flag.StringVar(&reviewerName, "name", "", "The display name of the reviewer (required)")
	flag.BoolVar(&yesFlag, "yes", false, "Confirm and bypass the interactive prompt")
	flag.Parse()

	if reviewerID == "" {
		flag.Usage()
		log.Fatal("Error: --id flag is required")
	}

	if reviewerName == "" {
		flag.Usage()
		log.Fatal("Error: --name flag is required")
	}

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	dbName := os.Getenv("MONGO_INITDB_DATABASE")
	if dbName == "" {
		dbName = "saas_platform"
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

	// Safety check: check if reviewer already exists
	existingRev, err := mongoStore.GetReviewerByID(ctx, reviewerID)
	if err == nil && existingRev != nil {
		log.Fatalf("Error: Reviewer with ID %q already exists", reviewerID)
	} else if err != nil && !errors.Is(err, mongo.ErrNoDocuments) {
		log.Fatalf("Error: Failed to check for existing reviewer: %v", err)
	}

	// Interactive confirmation if --yes is not set
	if !yesFlag {
		fmt.Printf("Are you sure you want to onboard reviewer %q (%s)? (y/N): ", reviewerID, reviewerName)
		var response string
		_, _ = fmt.Scanln(&response)
		response = strings.ToLower(strings.TrimSpace(response))
		if response != "y" && response != "yes" {
			fmt.Println("Aborted.")
			return
		}
	}

	// Generate cryptographically secure token using consolidated jwtutil helper
	token, err := jwtutil.GenerateSecureToken()
	if err != nil {
		log.Fatalf("Error: Failed to generate secure token: %v", err)
	}

	// Insert new reviewer
	rev := &models.Reviewer{
		ID:    reviewerID,
		Token: token,
		Name:  reviewerName,
	}

	if err := mongoStore.AddReviewer(ctx, rev); err != nil {
		log.Fatalf("Error: Failed to onboard reviewer: %v", err)
	}

	// Print the token EXACTLY ONCE to stdout
	fmt.Printf("\nSuccessfully onboarded reviewer %q!\n", reviewerID)
	fmt.Println("----------------------------------------------------------------------")
	fmt.Printf("Generated Reviewer Token: %s\n", token)
	fmt.Println("----------------------------------------------------------------------")
	fmt.Println("WARNING: This token is displayed ONLY ONCE. Copy it now.")
	fmt.Println("It cannot be retrieved again; if lost, the reviewer must be re-created.")
}
