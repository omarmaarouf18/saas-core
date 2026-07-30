package docgen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDocgenFreshness(t *testing.T) {
	// Paths relative to shared/infra/docgen
	repoRoot := filepath.Join("..", "..", "..")

	changed, _, err := UpdateApplicationMap(repoRoot, true)
	if err != nil {
		t.Fatalf("error checking application map freshness: %v", err)
	}

	if changed {
		t.Errorf("docs/APPLICATION_MAP.md is out of sync with HTTP route registrations! Run 'make docs' or 'go run tools/docgen/main.go' to regenerate and check in the updated APPLICATION_MAP.md.")
	}
}

func TestDocgenDriftCatching(t *testing.T) {
	// Let's verify that the AST parser dynamically detects route changes
	// We'll create a temporary workspace setup and modify a handler file to inject a new route
	tempDir, err := os.MkdirTemp("", "docgen-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Create services/auth-service/internal/handlers structure
	authHandlersDir := filepath.Join(tempDir, "services", "auth-service", "internal", "handlers")
	err = os.MkdirAll(authHandlersDir, 0755)
	if err != nil {
		t.Fatalf("failed to create temp auth handlers dir: %v", err)
	}

	// Write a mock auth.go with a RegisterRoutes containing a throwaway route
	mockAuthGo := `package handlers

import "net/http"

type Auth struct{}

func (a *Auth) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/auth/signup", a.Signup)
	mux.HandleFunc("/auth/throwaway_test_route", a.Throwaway)
}

func (a *Auth) Signup(w http.ResponseWriter, r *http.Request) {}

// Throwaway handles test route verification.
//
// Caller Permissions: Public
// Core Functionality: A dummy verification route.
// Read/Write Targets: None.
func (a *Auth) Throwaway(w http.ResponseWriter, r *http.Request) {}
`
	err = os.WriteFile(filepath.Join(authHandlersDir, "auth.go"), []byte(mockAuthGo), 0644)
	if err != nil {
		t.Fatalf("failed to write mock auth.go: %v", err)
	}

	// Also write minimal empty files for other 3 services so parser doesn't fail
	servicesToMock := []string{
		"chat-service/internal/handlers/chat.go",
		"notification-service/internal/handlers/handlers.go",
		"user-service/internal/handlers/handlers.go",
	}
	for _, s := range servicesToMock {
		dir := filepath.Join(tempDir, "services", filepath.Dir(s))
		err = os.MkdirAll(dir, 0755)
		if err != nil {
			t.Fatalf("failed to create mock dir: %v", err)
		}

		mockContent := `package handlers
import "net/http"
type Type struct{}
func (t *Type) RegisterRoutes(mux *http.ServeMux) {}
`
		// Specific struct/receiver naming matching the expected config
		if strings.Contains(s, "chat") {
			mockContent = `package handlers
import "net/http"
type Chat struct{}
func (c *Chat) RegisterRoutes(mux *http.ServeMux) {}
`
		} else if strings.Contains(s, "notification") {
			mockContent = `package handlers
import "net/http"
type Notification struct{}
func (n *Notification) RegisterRoutes(mux *http.ServeMux) {}
`
		} else if strings.Contains(s, "user") {
			mockContent = `package handlers
import "net/http"
type UserService struct{}
func (u *UserService) RegisterRoutes(mux *http.ServeMux) {}
`
		}

		err = os.WriteFile(filepath.Join(tempDir, "services", s), []byte(mockContent), 0644)
		if err != nil {
			t.Fatalf("failed to write mock file %s: %v", s, err)
		}
	}

	// Run GenerateEndpointsList on our tempDir mock workspace
	endpoints, err := GenerateEndpointsList(tempDir)
	if err != nil {
		t.Fatalf("failed to generate endpoints list from mock workspace: %v", err)
	}

	// Verify that the throwaway route is in the parsed endpoints list
	foundThrowaway := false
	for _, ep := range endpoints {
		if ep.Path == "/auth/throwaway_test_route" {
			foundThrowaway = true
			if ep.Method != "GET" {
				t.Errorf("expected Method GET for throwaway route, got %s", ep.Method)
			}
			if ep.Permissions != "Public" {
				t.Errorf("expected permissions 'Public', got %q", ep.Permissions)
			}
			if ep.HandlerName != "Throwaway" {
				t.Errorf("expected handler name 'Throwaway', got %s", ep.HandlerName)
			}
		}
	}

	if !foundThrowaway {
		t.Errorf("ast parser failed to detect the newly added throwaway route '/auth/throwaway_test_route'!")
	}
}

func TestGenerateMarkdownTable(t *testing.T) {
	endpoints := []Endpoint{
		{
			Method:      "POST",
			Path:        "/auth/login",
			Service:     "auth-service",
			Permissions: "Public",
			Function:    "Logs in user",
			Targets:     "Users DB",
		},
		{
			Method:      "GET",
			Path:        "/users/profile",
			Service:     "user-service",
			Permissions: "User JWT",
			Function:    "Get profile",
			Targets:     "Users DB",
		},
	}

	tbl := GenerateMarkdownTable(endpoints)
	if !strings.Contains(tbl, "| **`POST /auth/login`** | `auth-service` | Public | Logs in user | Users DB |") {
		t.Errorf("GenerateMarkdownTable missing expected row for POST /auth/login. Got:\n%s", tbl)
	}
	if !strings.Contains(tbl, "| **`GET /users/profile`** | `user-service` | User JWT | Get profile | Users DB |") {
		t.Errorf("GenerateMarkdownTable missing expected row for GET /users/profile. Got:\n%s", tbl)
	}
}
