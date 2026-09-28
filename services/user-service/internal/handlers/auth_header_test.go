package handlers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// A4: the six query-only session-JWT endpoints accept Authorization: Bearer
// with no query token. Query fallback keeps working (covered by existing
// tests); these cases pin the header path.
func TestAuthHeader_SessionEndpoints(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init(os.Getenv("JWT_SECRET"))
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	dbName := fmt.Sprintf("saas_authhdr_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	u := NewUserService(s, &config.Config{}, rdb)

	ownerToken, err := jwtutil.GenerateToken("owner-hdr", "owner", "owner-hdr", "owner-hdr@example.com")
	if err != nil {
		t.Fatalf("GenerateToken owner: %v", err)
	}
	empToken, err := jwtutil.GenerateToken("emp-hdr", "employee", "owner-hdr", "emp-hdr@example.com")
	if err != nil {
		t.Fatalf("GenerateToken employee: %v", err)
	}

	cases := []struct {
		name   string
		method string
		target string
		token  string
	}{
		{"GetWallet via header", "GET", "/users/wallet", ownerToken},
		{"GetLedger via header", "GET", "/users/ledger", ownerToken},
		{"Subscription via header", "GET", "/users/subscription", ownerToken},
		{"GetJob list via header", "GET", "/users/jobs/get", empToken},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(tc.method, tc.target, nil)
			req.Header.Set("Authorization", "Bearer "+tc.token)
			rec := httptest.NewRecorder()
			switch tc.target {
			case "/users/wallet":
				u.GetWallet(rec, req)
			case "/users/ledger":
				u.GetLedger(rec, req)
			case "/users/subscription":
				u.Subscription(rec, req)
			case "/users/jobs/get":
				u.GetJob(rec, req)
			}
			if rec.Code != http.StatusOK {
				t.Errorf("expected 200 via Authorization header, got %d (%s)", rec.Code, rec.Body.String())
			}
		})
	}
}
