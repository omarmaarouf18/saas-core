package handlers

// Handler wiring tests for ADR-0025 (working-hours-based out-of-service):
//  - ListServices attaches is_open_now/reopens_at without filtering.
//  - TrackJob rejects hours-closed bookings with 402 outside_working_hours.
//  - Create/UpdateService validate structured schedules with 400s.
// Pure evaluation/validation tables live in models/schedule_test.go.

import (
	"bytes"
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
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

func setupHoursHarness(t *testing.T) (*store.MongoDB, *UserService, context.Context, func()) {
	t.Helper()
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	dbName := fmt.Sprintf("saas_platform_hours_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		cancel()
		t.Skipf("Skipping working-hours test: MongoDB not available at %s (%v)", mongoURI, err)
	}
	mr, err := miniredis.Run()
	if err != nil {
		cancel()
		t.Fatalf("failed to start miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id": id, "role": "owner", "kyc_status": "approved",
			"is_active": true, "tenant_id": id,
		})
	}))
	cfg := &config.Config{
		AuthServiceURL:       mockAuthServer.URL,
		InternalServiceToken: "mock-internal-token",
		AppEnv:               "test",
	}
	u := NewUserService(s, cfg, rdb)
	cleanup := func() {
		mockAuthServer.Close()
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
		mr.Close()
		rdb.Close()
		cancel()
	}
	return s, u, ctx, cleanup
}

func seedHoursOpenSub(t *testing.T, s *store.MongoDB, ctx context.Context, tenantID string) {
	t.Helper()
	_ = s.UpsertSubscription(ctx, &models.Subscription{
		ID: "sub-hours-" + tenantID, TenantID: tenantID,
		Tier: models.PlanPaid, StartedAt: time.Now().UTC().Add(-time.Hour),
		ExpiresAt: time.Now().UTC().Add(24 * time.Hour),
	})
}

// perDayTodayOff builds a per-day table where today is off and every other
// weekday is open 09:00-17:00 — deterministically hours-closed right now,
// independent of wall-clock time.
func perDayTodayOff() []models.DaySchedule {
	today := strings.ToLower(time.Now().Weekday().String()[:3])
	days := []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
	out := make([]models.DaySchedule, 0, 7)
	for _, d := range days {
		if d == today {
			out = append(out, models.DaySchedule{Day: d, IsOff: true})
			continue
		}
		out = append(out, models.DaySchedule{Day: d, OpenTime: "09:00", CloseTime: "17:00"})
	}
	return out
}

func fullWeekSchedule() []models.DaySchedule {
	days := []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
	out := make([]models.DaySchedule, 0, 7)
	for _, d := range days {
		out = append(out, models.DaySchedule{Day: d, OpenTime: "09:00", CloseTime: "17:00"})
	}
	return out
}

func TestListServices_AttachesHoursFields(t *testing.T) {
	s, u, ctx, cleanup := setupHoursHarness(t)
	defer cleanup()

	seedHoursOpenSub(t, s, ctx, "hours-unknown-tenant")
	seedHoursOpenSub(t, s, ctx, "hours-off-tenant")
	s.CreateService(ctx, &models.Service{
		ID: "svc-hours-unknown", TenantID: "hours-unknown-tenant", Name: "Always Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})
	s.CreateService(ctx, &models.Service{
		ID: "svc-hours-off", TenantID: "hours-off-tenant", Name: "Resting Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
		ScheduleMode: models.ScheduleModePerDay, PerDaySchedule: perDayTodayOff(),
		Timezone: "Africa/Cairo",
	})

	req := httptest.NewRequest("GET", "/users/services", nil)
	rec := httptest.NewRecorder()
	u.ListServices(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Count    int              `json:"count"`
		Services []map[string]any `json:"services"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response JSON: %v", err)
	}
	// Hours-closed services stay listed (opposite rule from ADR-0024).
	if resp.Count != 2 {
		t.Fatalf("expected both services listed (no hours filtering), got %d: %s", resp.Count, rec.Body.String())
	}
	byTenant := map[string]map[string]any{}
	for _, svc := range resp.Services {
		byTenant[svc["tenant_id"].(string)] = svc
	}

	unknown := byTenant["hours-unknown-tenant"]
	if unknown["is_open_now"] != true {
		t.Errorf("unknown schedule must report is_open_now=true, got %v", unknown["is_open_now"])
	}
	// Explicit JSON null (key present, value null) per ADR-0025.
	reopens, hasKey := unknown["reopens_at"]
	if !hasKey || reopens != nil {
		t.Errorf("unknown schedule must report explicit null reopens_at, got present=%v value=%v", hasKey, reopens)
	}

	off := byTenant["hours-off-tenant"]
	if off["is_open_now"] != false {
		t.Errorf("today-off schedule must report is_open_now=false, got %v", off["is_open_now"])
	}
	reopensStr, _ := off["reopens_at"].(string)
	if reopensStr == "" {
		t.Fatalf("today-off schedule must report a computable reopens_at, got %v", off["reopens_at"])
	}
	if _, err := time.Parse(time.RFC3339, reopensStr); err != nil {
		t.Errorf("reopens_at must be RFC3339, got %q: %v", reopensStr, err)
	}
}

func TestTrackJob_HoursClosedRejected(t *testing.T) {
	s, u, ctx, cleanup := setupHoursHarness(t)
	defer cleanup()

	seedHoursOpenSub(t, s, ctx, "hours-track-closed")
	seedHoursOpenSub(t, s, ctx, "hours-track-open")
	s.CreateService(ctx, &models.Service{
		ID: "svc-track-closed", TenantID: "hours-track-closed", Name: "Closed Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
		ScheduleMode: models.ScheduleModePerDay, PerDaySchedule: perDayTodayOff(),
		Timezone: "Africa/Cairo",
	})
	s.CreateService(ctx, &models.Service{
		ID: "svc-track-open", TenantID: "hours-track-open", Name: "Open Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	postTrack := func(serviceID, userID string) *httptest.ResponseRecorder {
		tokenUser, _ := jwtutil.GenerateToken(userID, "user", userID, userID+"@example.com")
		raw, _ := json.Marshal(map[string]any{
			"service_id": serviceID, "user_id": tokenUser, "payment_method": "cod",
			"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
			"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
		})
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)
		return rec
	}

	rec := postTrack("svc-track-closed", "cust-hours-1")
	if rec.Code != http.StatusPaymentRequired {
		t.Fatalf("expected 402 for hours-closed service, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("rejection body is not JSON: %v", err)
	}
	if body["error"] != "outside_working_hours" {
		t.Errorf("expected error=outside_working_hours, got body: %s", rec.Body.String())
	}
	msg, _ := body["message"].(string)
	if !strings.Contains(msg, "out of service") {
		t.Errorf("expected out-of-service copy, got: %s", rec.Body.String())
	}
	if _, hasJob := body["job"]; hasJob {
		t.Errorf("rejected booking must not include a job record: %s", rec.Body.String())
	}

	// Unknown-schedule service on an open tenant proceeds (no behavior change).
	rec = postTrack("svc-track-open", "cust-hours-2")
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for open service, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestCreateService_ScheduleValidation(t *testing.T) {
	s, u, ctx, cleanup := setupHoursHarness(t)
	defer cleanup()

	ownerID := "hours-create-owner"
	seedHoursOpenSub(t, s, ctx, ownerID)
	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")

	postService := func(payload map[string]any) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+tokenOwner)
		rec := httptest.NewRecorder()
		u.CreateService(rec, req)
		return rec
	}
	base := map[string]any{
		"owner_id": ownerID, "name": "Sched Shop", "category": "delivery",
		"tenant_base_price": 10.0, "tenant_price_per_km": 1.0,
		"latitude": 30.0444, "longitude": 31.2357,
	}

	with := func(extra map[string]any) map[string]any {
		out := map[string]any{}
		for k, v := range base {
			out[k] = v
		}
		for k, v := range extra {
			out[k] = v
		}
		return out
	}

	rec := postService(with(map[string]any{"schedule_mode": "weekly", "open_time": "09:00", "close_time": "17:00"}))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for bad schedule_mode, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "invalid_schedule") {
		t.Errorf("expected invalid_schedule error, got: %s", rec.Body.String())
	}

	rec = postService(with(map[string]any{"open_time": "09:00", "close_time": "17:00"}))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for stray times without mode, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = postService(with(map[string]any{
		"schedule_mode": "same_daily", "open_time": "09:00", "close_time": "17:00",
		"timezone": "Africa/Cairo",
	}))
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for valid same_daily schedule, got %d: %s", rec.Code, rec.Body.String())
	}
	var created struct {
		Service models.Service `json:"service"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatalf("failed to parse create response: %v", err)
	}
	if created.Service.ScheduleMode != "same_daily" || created.Service.OpenTime != "09:00" || created.Service.Timezone != "Africa/Cairo" {
		t.Errorf("created service must echo stored schedule fields, got %+v", created.Service)
	}
}

func TestUpdateService_ScheduleValidation(t *testing.T) {
	s, u, ctx, cleanup := setupHoursHarness(t)
	defer cleanup()

	ownerID := "hours-update-owner"
	seedHoursOpenSub(t, s, ctx, ownerID)
	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	s.CreateService(ctx, &models.Service{
		ID: "svc-hours-upd", TenantID: ownerID, Name: "Upd Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	putService := func(payload map[string]any) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPut, "/users/services", bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+tokenOwner)
		rec := httptest.NewRecorder()
		u.UpdateService(rec, req)
		return rec
	}

	shortWeek := fullWeekSchedule()[:6]
	dayMaps := make([]map[string]any, 0, 6)
	for _, d := range shortWeek {
		dayMaps = append(dayMaps, map[string]any{"day": d.Day, "open_time": d.OpenTime, "close_time": d.CloseTime})
	}
	rec := putService(map[string]any{
		"service_id": "svc-hours-upd", "schedule_mode": "per_day", "per_day_schedule": dayMaps,
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for 6-entry per_day table, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "invalid_schedule") {
		t.Errorf("expected invalid_schedule error, got: %s", rec.Body.String())
	}

	fullMaps := make([]map[string]any, 0, 7)
	for _, d := range fullWeekSchedule() {
		fullMaps = append(fullMaps, map[string]any{"day": d.Day, "open_time": d.OpenTime, "close_time": d.CloseTime})
	}
	rec = putService(map[string]any{
		"service_id": "svc-hours-upd", "schedule_mode": "per_day",
		"per_day_schedule": fullMaps, "timezone": "Africa/Cairo",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for valid per_day update, got %d: %s", rec.Code, rec.Body.String())
	}
	stored := s.GetServiceByID(ctx, "svc-hours-upd")
	if stored == nil || stored.ScheduleMode != "per_day" || len(stored.PerDaySchedule) != 7 || stored.Timezone != "Africa/Cairo" {
		t.Fatalf("stored service must persist the schedule, got %+v", stored)
	}

	// Explicit clear returns the service to "unknown" (always open).
	rec = putService(map[string]any{"service_id": "svc-hours-upd", "schedule_mode": ""})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for schedule clear, got %d: %s", rec.Code, rec.Body.String())
	}
	stored = s.GetServiceByID(ctx, "svc-hours-upd")
	if stored == nil || stored.ScheduleMode != "" {
		t.Fatalf("schedule_mode must be cleared, got %+v", stored)
	}
	if isOpen, _ := models.EvaluateServiceSchedule(*stored, time.Now().UTC()); !isOpen {
		t.Errorf("cleared schedule must evaluate as open")
	}
}
