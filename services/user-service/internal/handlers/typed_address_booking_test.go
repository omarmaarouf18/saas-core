package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

func postTrackWithVersion(t *testing.T, u *UserService, version string, body map[string]any) *httptest.ResponseRecorder {
	t.Helper()
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/users/jobs/track", strings.NewReader(string(raw)))
	req.Header.Set("Content-Type", "application/json")
	if version != "" {
		req.Header.Set("X-App-Version", version)
	}
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)
	return rec
}

func setupTypedAddressBookingHarness(t *testing.T) (*UserService, any, context.Context, string, func()) {
	t.Helper()
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	u, _ := trackJobClosedStatusHarness(t, s)

	ownerID := "addr-owner-1"
	seedClosedStatusSub(t, s, ctx, ownerID, models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-addr-1", TenantID: ownerID, Name: "Typed Address Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	tokenUser, _ := jwtutil.GenerateToken("cust-addr-1", "user", ownerID, "cust@example.com")
	return u, s, ctx, tokenUser, cleanup
}

func TestTypedAddress_V210_AddressRequired(t *testing.T) {
	u, _, _, tokenUser, cleanup := setupTypedAddressBookingHarness(t)
	defer cleanup()

	base := func() map[string]any {
		return map[string]any{
			"service_id": "svc-addr-1", "user_id": tokenUser, "payment_method": "cod",
			"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
			"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
		}
	}

	// 1. Missing location.address
	payload1 := base()
	payload1["destination"] = map[string]any{
		"latitude": 30.05, "longitude": 31.24,
		"address": "4 شارع التحرير، الدقي",
	}
	rec1 := postTrackWithVersion(t, u, "2.1.0", payload1)
	if rec1.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for missing location.address on 2.1.0, got %d: %s", rec1.Code, rec1.Body.String())
	}
	var body1 map[string]string
	_ = json.Unmarshal(rec1.Body.Bytes(), &body1)
	if body1["code"] != "address_required" || !strings.Contains(body1["error"], "location.address") {
		t.Errorf("expected address_required naming location.address, got %+v", body1)
	}

	// 2. Whitespace-only location.address
	payload2 := base()
	payload2["location"] = map[string]any{
		"latitude": 30.0444, "longitude": 31.2357,
		"address": "    ",
	}
	payload2["destination"] = map[string]any{
		"latitude": 30.05, "longitude": 31.24,
		"address": "4 شارع التحرير، الدقي",
	}
	rec2 := postTrackWithVersion(t, u, "2.1.0", payload2)
	if rec2.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for whitespace location.address, got %d: %s", rec2.Code, rec2.Body.String())
	}
	var body2 map[string]string
	_ = json.Unmarshal(rec2.Body.Bytes(), &body2)
	if body2["code"] != "address_required" {
		t.Errorf("expected address_required, got %+v", body2)
	}

	// 3. Missing destination.address
	payload3 := base()
	payload3["location"] = map[string]any{
		"latitude": 30.0444, "longitude": 31.2357,
		"address": "15 شارع قصر النيل",
	}
	rec3 := postTrackWithVersion(t, u, "2.1.0", payload3)
	if rec3.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for missing destination.address on 2.1.0, got %d: %s", rec3.Code, rec3.Body.String())
	}
	var body3 map[string]string
	_ = json.Unmarshal(rec3.Body.Bytes(), &body3)
	if body3["code"] != "address_required" || !strings.Contains(body3["error"], "destination.address") {
		t.Errorf("expected address_required naming destination.address, got %+v", body3)
	}
}

func TestTypedAddress_V210_AddressTooShort(t *testing.T) {
	u, _, _, tokenUser, cleanup := setupTypedAddressBookingHarness(t)
	defer cleanup()

	base := func() map[string]any {
		return map[string]any{
			"service_id": "svc-addr-1", "user_id": tokenUser, "payment_method": "cod",
			"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
			"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
		}
	}

	// 1. location.address with 4 runes
	p1 := base()
	p1["location"] = map[string]any{"latitude": 30.0444, "longitude": 31.2357, "address": "1234"}
	p1["destination"] = map[string]any{"latitude": 30.05, "longitude": 31.24, "address": "شارع التحرير"}
	rec1 := postTrackWithVersion(t, u, "2.1.0", p1)
	if rec1.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for 4-rune location.address, got %d: %s", rec1.Code, rec1.Body.String())
	}
	var b1 map[string]string
	_ = json.Unmarshal(rec1.Body.Bytes(), &b1)
	if b1["code"] != "address_too_short" || !strings.Contains(b1["error"], "location.address") {
		t.Errorf("expected address_too_short naming location.address, got %+v", b1)
	}

	// 2. destination.address with 4 runes
	p2 := base()
	p2["location"] = map[string]any{"latitude": 30.0444, "longitude": 31.2357, "address": "شارع التحرير"}
	p2["destination"] = map[string]any{"latitude": 30.05, "longitude": 31.24, "address": "مصر1"}
	rec2 := postTrackWithVersion(t, u, "2.1.0", p2)
	if rec2.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for 4-rune destination.address, got %d: %s", rec2.Code, rec2.Body.String())
	}
	var b2 map[string]string
	_ = json.Unmarshal(rec2.Body.Bytes(), &b2)
	if b2["code"] != "address_too_short" || !strings.Contains(b2["error"], "destination.address") {
		t.Errorf("expected address_too_short naming destination.address, got %+v", b2)
	}

	// 3. 5 characters but 2 are control chars -> 3 runes after sanitizing -> address_too_short
	p3 := base()
	p3["location"] = map[string]any{"latitude": 30.0444, "longitude": 31.2357, "address": "abc\x01\x02"}
	p3["destination"] = map[string]any{"latitude": 30.05, "longitude": 31.24, "address": "شارع التحرير"}
	rec3 := postTrackWithVersion(t, u, "2.1.0", p3)
	if rec3.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for sanitized 3-rune address, got %d: %s", rec3.Code, rec3.Body.String())
	}
	var b3 map[string]string
	_ = json.Unmarshal(rec3.Body.Bytes(), &b3)
	if b3["code"] != "address_too_short" {
		t.Errorf("expected address_too_short, got %+v", b3)
	}
}

func TestTypedAddress_V210_ValidRoundTripAndStored(t *testing.T) {
	u, storeAny, ctx, tokenUser, cleanup := setupTypedAddressBookingHarness(t)
	defer cleanup()
	s := storeAny.(interface {
		GetJob(ctx context.Context, id string) *models.Job
	})

	payload := map[string]any{
		"service_id": "svc-addr-1", "user_id": tokenUser, "payment_method": "cod",
		"location": map[string]any{
			"latitude":  30.0444,
			"longitude": 31.2357,
			"address":   "15 شارع قصر النيل",
			"building":  "عمارة 12",
			"floor":     "3",
			"apartment": "7",
		},
		"destination": map[string]any{
			"latitude":  30.05,
			"longitude": 31.24,
			"address":   "4 شارع التحرير، الدقي",
			"building":  "برج النيل",
			"floor":     "الدور العاشر",
			"apartment": "101",
		},
	}

	rec := postTrackWithVersion(t, u, "2.1.0", payload)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for valid 2.1.0 booking, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Job models.Job `json:"job"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	// Verify response fields
	if resp.Job.Location.Building != "عمارة 12" || resp.Job.Location.Floor != "3" || resp.Job.Location.Apartment != "7" {
		t.Errorf("response location structured details mismatch: %+v", resp.Job.Location)
	}
	if resp.Job.Destination.Building != "برج النيل" || resp.Job.Destination.Floor != "الدور العاشر" || resp.Job.Destination.Apartment != "101" {
		t.Errorf("response destination structured details mismatch: %+v", resp.Job.Destination)
	}

	// Verify database persistence
	stored := s.GetJob(ctx, resp.Job.ID)
	if stored == nil {
		t.Fatalf("stored job not found in DB")
	}
	if stored.Location.Address != "15 شارع قصر النيل" ||
		stored.Location.Building != "عمارة 12" ||
		stored.Location.Floor != "3" ||
		stored.Location.Apartment != "7" {
		t.Errorf("stored location structured details mismatch: %+v", stored.Location)
	}
	if stored.Destination.Address != "4 شارع التحرير، الدقي" ||
		stored.Destination.Building != "برج النيل" ||
		stored.Destination.Floor != "الدور العاشر" ||
		stored.Destination.Apartment != "101" {
		t.Errorf("stored destination structured details mismatch: %+v", stored.Destination)
	}
}

func TestTypedAddress_LegacyAndNoHeader_WithoutAddressAccepted(t *testing.T) {
	u, _, _, tokenUser, cleanup := setupTypedAddressBookingHarness(t)
	defer cleanup()

	payload := map[string]any{
		"service_id": "svc-addr-1", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
	}

	// App 2.0.0 without address -> 201
	rec200 := postTrackWithVersion(t, u, "2.0.0", payload)
	if rec200.Code != http.StatusCreated {
		t.Fatalf("expected 201 for 2.0.0 booking without address, got %d: %s", rec200.Code, rec200.Body.String())
	}

	// No header without address -> 201
	recNoHeader := postTrackWithVersion(t, u, "", payload)
	if recNoHeader.Code != http.StatusCreated {
		t.Fatalf("expected 201 for no-header booking without address, got %d: %s", recNoHeader.Code, recNoHeader.Body.String())
	}
}

func TestTypedAddress_OverCapFieldsRejectedForAnyVersion(t *testing.T) {
	u, _, _, tokenUser, cleanup := setupTypedAddressBookingHarness(t)
	defer cleanup()

	for _, ver := range []string{"2.1.0", "2.0.0", ""} {
		t.Run("version_"+ver, func(t *testing.T) {
			base := func() map[string]any {
				return map[string]any{
					"service_id": "svc-addr-1", "user_id": tokenUser, "payment_method": "cod",
					"location": map[string]any{
						"latitude": 30.0444, "longitude": 31.2357,
						"address": "شارع قصر النيل الرئيسي",
					},
					"destination": map[string]any{
						"latitude": 30.05, "longitude": 31.24,
						"address": "شارع التحرير بالدقي",
					},
				}
			}

			// Building over 50 runes
			pBuilding := base()
			pBuilding["location"].(map[string]any)["building"] = strings.Repeat("ب", 51)
			rec := postTrackWithVersion(t, u, ver, pBuilding)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("version %q: expected 400 for over-cap building, got %d: %s", ver, rec.Code, rec.Body.String())
			}
			var bBuilding map[string]string
			_ = json.Unmarshal(rec.Body.Bytes(), &bBuilding)
			if bBuilding["code"] != "building_too_long" {
				t.Errorf("version %q: expected building_too_long, got %+v", ver, bBuilding)
			}

			// Floor over 20 runes
			pFloor := base()
			pFloor["location"].(map[string]any)["floor"] = strings.Repeat("د", 21)
			rec = postTrackWithVersion(t, u, ver, pFloor)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("version %q: expected 400 for over-cap floor, got %d: %s", ver, rec.Code, rec.Body.String())
			}
			var bFloor map[string]string
			_ = json.Unmarshal(rec.Body.Bytes(), &bFloor)
			if bFloor["code"] != "floor_too_long" {
				t.Errorf("version %q: expected floor_too_long, got %+v", ver, bFloor)
			}

			// Apartment over 20 runes
			pApt := base()
			pApt["location"].(map[string]any)["apartment"] = strings.Repeat("ش", 21)
			rec = postTrackWithVersion(t, u, ver, pApt)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("version %q: expected 400 for over-cap apartment, got %d: %s", ver, rec.Code, rec.Body.String())
			}
			var bApt map[string]string
			_ = json.Unmarshal(rec.Body.Bytes(), &bApt)
			if bApt["code"] != "apartment_too_long" {
				t.Errorf("version %q: expected apartment_too_long, got %+v", ver, bApt)
			}
		})
	}
}

func TestTypedAddress_ReadDTOsProjection(t *testing.T) {
	job := &models.Job{
		ID:         "job-read-test",
		OwnerID:    "owner-1",
		UserID:     "user-1",
		EmployeeID: "emp-1",
		Status:     models.JobStatusActive,
		SubStatus:  models.SubStatusHeadingToPickup,
		Location: models.Location{
			Latitude:  30.0444,
			Longitude: 31.2357,
			Address:   "15 شارع قصر النيل",
			Building:  "عمارة 12",
			Floor:     "3",
			Apartment: "7",
		},
		Destination: models.Location{
			Latitude:  30.05,
			Longitude: 31.24,
			Address:   "4 شارع التحرير",
			Building:  "برج النيل",
			Floor:     "10",
			Apartment: "101",
		},
	}

	// 1. Owner DTO
	ownerDTO := models.NewOwnerJobResponse(job)
	if ownerDTO.Location.Building != "عمارة 12" || ownerDTO.Location.Floor != "3" || ownerDTO.Location.Apartment != "7" {
		t.Errorf("ownerDTO location structured details mismatch: %+v", ownerDTO.Location)
	}
	if ownerDTO.Destination.Building != "برج النيل" || ownerDTO.Destination.Floor != "10" || ownerDTO.Destination.Apartment != "101" {
		t.Errorf("ownerDTO destination structured details mismatch: %+v", ownerDTO.Destination)
	}

	ownerJSON, err := json.Marshal(ownerDTO)
	if err != nil {
		t.Fatalf("failed to marshal ownerDTO: %v", err)
	}
	if !strings.Contains(string(ownerJSON), `"building":"عمارة 12"`) ||
		!strings.Contains(string(ownerJSON), `"floor":"3"`) ||
		!strings.Contains(string(ownerJSON), `"apartment":"7"`) {
		t.Errorf("ownerJSON missing structured location fields: %s", string(ownerJSON))
	}

	// 2. Employee (Courier) DTO
	empDTO := models.NewEmployeeJobResponse(job, "emp-1")
	if empDTO.Location.Building != "عمارة 12" || empDTO.Location.Floor != "3" || empDTO.Location.Apartment != "7" {
		t.Errorf("empDTO location structured details mismatch: %+v", empDTO.Location)
	}
	if empDTO.Destination.Building != "برج النيل" || empDTO.Destination.Floor != "10" || empDTO.Destination.Apartment != "101" {
		t.Errorf("empDTO destination structured details mismatch: %+v", empDTO.Destination)
	}

	empJSON, err := json.Marshal(empDTO)
	if err != nil {
		t.Fatalf("failed to marshal empDTO: %v", err)
	}
	if !strings.Contains(string(empJSON), `"building":"عمارة 12"`) ||
		!strings.Contains(string(empJSON), `"floor":"3"`) ||
		!strings.Contains(string(empJSON), `"apartment":"7"`) {
		t.Errorf("empJSON missing structured location fields: %s", string(empJSON))
	}

	// 3. Customer DTO
	custDTO := models.NewCustomerJobResponse(job)
	if custDTO.Location.Building != "عمارة 12" || custDTO.Location.Floor != "3" || custDTO.Location.Apartment != "7" {
		t.Errorf("custDTO location structured details mismatch: %+v", custDTO.Location)
	}
	if custDTO.Destination.Building != "برج النيل" || custDTO.Destination.Floor != "10" || custDTO.Destination.Apartment != "101" {
		t.Errorf("custDTO destination structured details mismatch: %+v", custDTO.Destination)
	}

	custJSON, err := json.Marshal(custDTO)
	if err != nil {
		t.Fatalf("failed to marshal custDTO: %v", err)
	}
	if !strings.Contains(string(custJSON), `"building":"عمارة 12"`) ||
		!strings.Contains(string(custJSON), `"floor":"3"`) ||
		!strings.Contains(string(custJSON), `"apartment":"7"`) {
		t.Errorf("custJSON missing structured location fields: %s", string(custJSON))
	}

	// 4. Empty omitempty test: when empty, keys should not be in JSON
	emptyJob := &models.Job{
		ID:          "job-empty-test",
		OwnerID:     "owner-1",
		UserID:      "user-1",
		Status:      models.JobStatusPending,
		Location:    models.Location{Latitude: 30.0, Longitude: 31.0, Address: "Address only"},
		Destination: models.Location{Latitude: 30.0, Longitude: 31.0, Address: "Destination only"},
	}
	emptyOwnerJSON, _ := json.Marshal(models.NewOwnerJobResponse(emptyJob))
	if strings.Contains(string(emptyOwnerJSON), `"building"`) ||
		strings.Contains(string(emptyOwnerJSON), `"floor"`) ||
		strings.Contains(string(emptyOwnerJSON), `"apartment"`) {
		t.Errorf("empty fields must be omitted from JSON: %s", string(emptyOwnerJSON))
	}
}
