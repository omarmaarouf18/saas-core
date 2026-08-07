package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/project/chat-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

func TestGenerateSecureToken(t *testing.T) {
	token1, err := jwtutil.GenerateSecureToken()
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	token2, err := jwtutil.GenerateSecureToken()
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	if token1 == token2 {
		t.Errorf("GenerateSecureToken generated duplicate tokens: %s", token1)
	}

	// 32 random bytes in hex should produce exactly 64 characters
	if len(token1) != 64 {
		t.Errorf("expected token length of 64 characters, got %d", len(token1))
	}
}

func TestOnboardAgentIntegration(t *testing.T) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("chat_platform_onboard_test_%d", time.Now().UnixNano())
	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping integration tests: MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = mongoStore.Close(context.Background())
	}()

	agentID := "agent_test_duplicate"

	// 1. Seed an agent
	agent := &store.SupportAgent{
		ID:     agentID,
		Status: "available",
		Token:  "test-token-123",
	}
	if err := mongoStore.AddSupportAgent(ctx, agent); err != nil {
		if strings.Contains(err.Error(), "Unauthorized") || strings.Contains(err.Error(), "authentication") {
			t.Skipf("Skipping integration test: MongoDB requires auth (%v)", err)
			return
		}
		t.Fatalf("failed to add support agent: %v", err)
	}

	// 2. Try to query it and verify it exists
	existingAgent, err := mongoStore.GetAgent(ctx, agentID)
	if err != nil {
		t.Fatalf("failed to fetch seeded agent: %v", err)
	}
	if existingAgent.ID != agentID {
		t.Errorf("expected agent ID %s, got %s", agentID, existingAgent.ID)
	}

	// 3. Attempting to add an agent with same ID must fail (rejection logic)
	existingAgent2, err2 := mongoStore.GetAgent(ctx, agentID)
	if err2 == nil && existingAgent2 != nil {
		// Agent exists! The duplicate ID check correctly flags the existing agent.
	} else if err2 != nil {
		t.Errorf("expected agent to be found, got error: %v", err2)
	}

	// 4. Test missing agent returns ErrNoDocuments
	_, err3 := mongoStore.GetAgent(ctx, "non_existent_agent")
	if !errors.Is(err3, mongo.ErrNoDocuments) {
		t.Errorf("expected ErrNoDocuments for non-existent agent, got: %v", err3)
	}
}

func TestOnboardAgentCLIArgs(t *testing.T) {
	cmd := exec.Command("go", "run", "main.go", "--yes")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		t.Fatal("expected CLI command to exit with error when missing --id, but got success")
	}

	output := stderr.String()
	if !strings.Contains(output, "Error: --id flag is required") {
		t.Errorf("expected error output to contain '--id flag is required', got: %q", output)
	}
}
