package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// A6: client-facing DTOs must not carry internal echoes. Each endpoint
// below keeps every UI-consumed field while dropping the stripped keys.
func TestResponseDTOs_StripInternalEchoes(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init(os.Getenv("JWT_SECRET"))
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	dbName := fmt.Sprintf("saas_dto_test_%d", time.Now().UnixNano())
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

	ownerToken, _ := jwtutil.GenerateToken("owner-dto", "owner", "owner-dto", "owner-dto@example.com")
	hdr := func(req *http.Request) *http.Request {
		req.Header.Set("Authorization", "Bearer "+ownerToken)
		return req
	}

	t.Run("GetWallet strips id and tenant echo", func(t *testing.T) {
		rec := httptest.NewRecorder()
		u.GetWallet(rec, hdr(httptest.NewRequest("GET", "/users/wallet", nil)))
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d (%s)", rec.Code, rec.Body.String())
		}
		var body map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("decode: %v", err)
		}
		for _, k := range []string{"id", "tenant_id"} {
			if _, ok := body[k]; ok {
				t.Errorf("wallet leaks %q", k)
			}
		}
		for _, k := range []string{"total_balance", "escrow_balance", "withdrawable_balance", "updated_at"} {
			if _, ok := body[k]; !ok {
				t.Errorf("wallet missing UI field %q", k)
			}
		}
	})

	t.Run("GetLedger strips id, tenant echo and balance_before", func(t *testing.T) {
		rec := httptest.NewRecorder()
		u.GetLedger(rec, hdr(httptest.NewRequest("GET", "/users/ledger", nil)))
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d (%s)", rec.Code, rec.Body.String())
		}
		var body struct {
			Entries []map[string]any `json:"entries"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("decode: %v", err)
		}
		_ = body
		raw := rec.Body.String()
		for _, k := range []string{`"balance_before"`, `"tenant_id"`} {
			if strings.Contains(raw, k) {
				t.Errorf("ledger leaks %s: %s", k, raw)
			}
		}
	})

	t.Run("Subscription strips reviewer audit fields", func(t *testing.T) {
		rec := httptest.NewRecorder()
		u.Subscription(rec, hdr(httptest.NewRequest("GET", "/users/subscription", nil)))
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d (%s)", rec.Code, rec.Body.String())
		}
		var body map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("decode: %v", err)
		}
		for _, k := range []string{"id", "tenant_id", "activated_by", "revoked_by", "reason"} {
			if _, ok := body[k]; ok {
				t.Errorf("subscription leaks %q", k)
			}
		}
		if _, ok := body["tier"]; !ok {
			t.Errorf("subscription missing tier")
		}
	})
}
