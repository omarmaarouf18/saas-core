package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

func TestListServices_CoordinateBoundsValidation(t *testing.T) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_list_svc_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping ListServices test: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	cfg := &config.Config{}
	u := NewUserService(s, cfg, rdb)

	// (a) Out-of-range lat (999) is rejected with 400 invalid_coordinates when near_by=true
	t.Run("Invalid Latitude Bounds (near_by=true)", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/services?near_by=true&lat=999.0&lon=31.2357", nil)
		rec := httptest.NewRecorder()
		u.ListServices(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("Expected 400 Bad Request for out-of-range lat, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]string
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("Failed to parse response JSON: %v", err)
		}
		if resp["error"] != "invalid_coordinates" {
			t.Errorf("Expected error 'invalid_coordinates', got %q", resp["error"])
		}
	})

	// (b) Out-of-range lon (999) is rejected with 400 invalid_coordinates
	t.Run("Invalid Longitude Bounds", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/services?lat=30.0444&lon=999.0", nil)
		rec := httptest.NewRecorder()
		u.ListServices(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("Expected 400 Bad Request for out-of-range lon, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]string
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("Failed to parse response JSON: %v", err)
		}
		if resp["error"] != "invalid_coordinates" {
			t.Errorf("Expected error 'invalid_coordinates', got %q", resp["error"])
		}
	})

	// (c) Valid coordinates still return results normally
	t.Run("Valid Coordinates (near_by=true)", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/services?near_by=true&lat=30.0444&lon=31.2357", nil)
		rec := httptest.NewRecorder()
		u.ListServices(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for valid coordinates, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("Failed to parse response JSON: %v", err)
		}
		if _, ok := resp["services"]; !ok {
			t.Errorf("Expected response to contain 'services' key")
		}
	})

	// (d) Omitting lat/lon (falling back to defaults) still works without triggering validation error
	t.Run("Omitted Coordinates Default Fallback", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/services", nil)
		rec := httptest.NewRecorder()
		u.ListServices(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for default coordinates fallback, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("Failed to parse response JSON: %v", err)
		}
		if _, ok := resp["services"]; !ok {
			t.Errorf("Expected response to contain 'services' key")
		}
	})
}
