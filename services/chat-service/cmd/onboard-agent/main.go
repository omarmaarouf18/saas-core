// Package main implements a standalone CLI tool to onboard support agents.
// Usage:
//
//	MONGO_URI=mongodb://localhost:27017 go run ./services/chat-service/cmd/onboard-agent --id=agent_omar
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

	"github.com/project/chat-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

func main() {
	var agentID string
	var yesFlag bool

	flag.StringVar(&agentID, "id", "", "The unique identifier of the support agent (required)")
	flag.BoolVar(&yesFlag, "yes", false, "Confirm and bypass the interactive prompt")
	flag.Parse()

	if agentID == "" {
		flag.Usage()
		log.Fatal("Error: --id flag is required")
	}

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	dbName := os.Getenv("MONGO_INITDB_DATABASE")
	if dbName == "" {
		dbName = "chat_db"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		log.Fatalf("Error: Failed to connect to MongoDB: %v", err)
	}
	defer func() {
		_ = mongoStore.Close(context.Background())
	}()

	// Safety check: check if agent already exists
	existingAgent, err := mongoStore.GetAgent(ctx, agentID)
	if err == nil && existingAgent != nil {
		log.Fatalf("Error: Support agent with ID %q already exists", agentID)
	} else if err != nil && !errors.Is(err, mongo.ErrNoDocuments) {
		log.Fatalf("Error: Failed to check for existing support agent: %v", err)
	}

	// Interactive confirmation if --yes is not set
	if !yesFlag {
		fmt.Printf("Are you sure you want to onboard support agent %q? (y/N): ", agentID)
		var response string
		_, _ = fmt.Scanln(&response)
		response = strings.ToLower(strings.TrimSpace(response))
		if response != "y" && response != "yes" {
			fmt.Println("Aborted.")
			return
		}
	}

	// Generate cryptographically secure token
	token, err := jwtutil.GenerateSecureToken()
	if err != nil {
		log.Fatalf("Error: Failed to generate secure token: %v", err)
	}

	// Insert new support agent with status available
	agent := &store.SupportAgent{
		ID:     agentID,
		Status: "available",
		Token:  token,
	}

	if err := mongoStore.AddSupportAgent(ctx, agent); err != nil {
		log.Fatalf("Error: Failed to onboard support agent: %v", err)
	}

	// Print the token EXACTLY ONCE to stdout
	fmt.Printf("\nSuccessfully onboarded support agent %q!\n", agentID)
	fmt.Println("----------------------------------------------------------------------")
	fmt.Printf("Generated Token: %s\n", token)
	fmt.Println("----------------------------------------------------------------------")
	fmt.Println("WARNING: This token is displayed ONLY ONCE. Copy it now.")
	fmt.Println("It cannot be retrieved again; if lost, the agent must be re-created.")
}
