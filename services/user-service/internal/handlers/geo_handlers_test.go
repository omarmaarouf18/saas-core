package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/geo"
	"github.com/redis/go-redis/v9"
)

const geoTestJWTSecret = "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"

func newGeoTestHarness(t *testing.T, googleHandler http.HandlerFunc, apiKey string) (*UserService, *http.ServeMux, *httptest.Server, func()) {
	t.Helper()
	t.Setenv("JWT_SECRET", geoTestJWTSecret)
	jwtutil.Init(geoTestJWTSecret)

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis.Run: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})

	googleSrv := httptest.NewServer(googleHandler)

	cfg := &config.Config{
		AppEnv:              "test",
		JWTSecret:           geoTestJWTSecret,
		GoogleMapsServerKey: apiKey,
	}
	u := NewUserService(nil, cfg, rdb)
	u.SetGeoClient(geo.NewClient(geo.Config{
		APIKey:         apiKey,
		PlacesBaseURL:  googleSrv.URL,
		GeocodeBaseURL: googleSrv.URL,
	}))

	mux := http.NewServeMux()
	u.RegisterRoutes(mux)

	cleanup := func() {
		u.Close()
		googleSrv.Close()
		_ = rdb.Close()
		mr.Close()
	}
	return u, mux, googleSrv, cleanup
}

func makeGeoJWT(t *testing.T, userID, role string) string {
	t.Helper()
	tok, err := jwtutil.GenerateToken(userID, role, "tenant-1", userID+"@example.com")
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	return tok
}

func TestGeoHandlers_HappyPathsAndEgyptBias(t *testing.T) {
	var seenAutocompleteBody map[string]any
	var seenPlaceSession, seenPlaceRegion, seenPlaceLang string
	var seenReverseRegion, seenReverseLang string

	_, mux, _, cleanup := newGeoTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/v1/places:autocomplete":
			if err := json.NewDecoder(r.Body).Decode(&seenAutocompleteBody); err != nil {
				t.Fatalf("decode autocomplete req: %v", err)
			}
			_ = json.NewEncoder(w).Encode(map[string]any{
				"suggestions": []map[string]any{
					{
						"placePrediction": map[string]any{
							"placeId": "ChIJ_1",
							"structuredFormat": map[string]any{
								"mainText":      map[string]any{"text": "15 شارع قصر النيل"},
								"secondaryText": map[string]any{"text": "وسط البلد، القاهرة"},
							},
						},
					},
				},
			})
		case strings.HasPrefix(r.URL.Path, "/v1/places/"):
			seenPlaceSession = r.URL.Query().Get("sessionToken")
			seenPlaceRegion = r.URL.Query().Get("regionCode")
			seenPlaceLang = r.URL.Query().Get("languageCode")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":                    "ChIJ_1",
				"shortFormattedAddress": "15 شارع قصر النيل، عابدين",
				"location":              map[string]any{"latitude": 30.0444, "longitude": 31.2357},
				"addressComponents": []map[string]any{
					{"longText": "عابدين", "types": []string{"sublocality_level_1", "political"}},
				},
			})
		case r.URL.Path == "/maps/api/geocode/json":
			seenReverseRegion = r.URL.Query().Get("region")
			seenReverseLang = r.URL.Query().Get("language")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"status": "OK",
				"results": []map[string]any{
					{
						"formatted_address": "15 Kasr El Nil, Qasr El Nil, Cairo",
						"address_components": []map[string]any{
							{"long_name": "Qasr El Nil", "types": []string{"administrative_area_level_2"}},
						},
					},
				},
			})
		default:
			t.Fatalf("unexpected upstream path: %s", r.URL.Path)
		}
	}, "test-google-server-key")
	defer cleanup()

	// All roles (user, owner, employee) are allowed.
	customerToken := makeGeoJWT(t, "cust-1", "user")
	ownerToken := makeGeoJWT(t, "owner-1", "owner")
	empToken := makeGeoJWT(t, "emp-1", "employee")

	// 1. Autocomplete (Arabic)
	req1 := httptest.NewRequest(http.MethodGet, "/users/geo/autocomplete?q="+url.QueryEscape("قصر النيل")+"&session=sess-abc", nil)
	req1.Header.Set("Authorization", "Bearer "+customerToken)
	req1.Header.Set("Accept-Language", "ar-EG,en;q=0.8")
	rec1 := httptest.NewRecorder()
	mux.ServeHTTP(rec1, req1)
	if rec1.Code != http.StatusOK {
		t.Fatalf("autocomplete status = %d, body=%s", rec1.Code, rec1.Body.String())
	}
	var acResp struct {
		Suggestions []geo.Suggestion `json:"suggestions"`
	}
	if err := json.Unmarshal(rec1.Body.Bytes(), &acResp); err != nil {
		t.Fatalf("decode autocomplete: %v", err)
	}
	if len(acResp.Suggestions) != 1 || acResp.Suggestions[0].PlaceID != "ChIJ_1" {
		t.Errorf("unexpected suggestions: %+v", acResp.Suggestions)
	}
	if seenAutocompleteBody["regionCode"] != "eg" || seenAutocompleteBody["languageCode"] != "ar" {
		t.Errorf("unexpected upstream autocomplete params: %+v", seenAutocompleteBody)
	}

	// 2. Place details (Owner role, Arabic)
	req2 := httptest.NewRequest(http.MethodGet, "/users/geo/place?place_id=ChIJ_1&session=sess-abc", nil)
	req2.Header.Set("Authorization", "Bearer "+ownerToken)
	req2.Header.Set("Accept-Language", "ar")
	rec2 := httptest.NewRecorder()
	mux.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusOK {
		t.Fatalf("place status = %d, body=%s", rec2.Code, rec2.Body.String())
	}
	var placeResp geo.PlaceDetails
	if err := json.Unmarshal(rec2.Body.Bytes(), &placeResp); err != nil {
		t.Fatalf("decode place: %v", err)
	}
	if placeResp.Lat != 30.0444 || placeResp.Lng != 31.2357 || placeResp.Area != "عابدين" {
		t.Errorf("unexpected place details: %+v", placeResp)
	}
	if seenPlaceSession != "sess-abc" || seenPlaceRegion != "eg" || seenPlaceLang != "ar" {
		t.Errorf("unexpected place query params: session=%q region=%q lang=%q", seenPlaceSession, seenPlaceRegion, seenPlaceLang)
	}

	// 3. Reverse geocode (Employee role, English)
	req3 := httptest.NewRequest(http.MethodGet, "/users/geo/reverse?lat=30.0444&lng=31.2357", nil)
	req3.Header.Set("Authorization", "Bearer "+empToken)
	req3.Header.Set("Accept-Language", "en-US")
	rec3 := httptest.NewRecorder()
	mux.ServeHTTP(rec3, req3)
	if rec3.Code != http.StatusOK {
		t.Fatalf("reverse status = %d, body=%s", rec3.Code, rec3.Body.String())
	}
	var revResp geo.ReverseResult
	if err := json.Unmarshal(rec3.Body.Bytes(), &revResp); err != nil {
		t.Fatalf("decode reverse: %v", err)
	}
	if revResp.Address != "15 Kasr El Nil, Qasr El Nil, Cairo" || revResp.Area != "Qasr El Nil" {
		t.Errorf("unexpected reverse result: %+v", revResp)
	}
	if seenReverseRegion != "eg" || seenReverseLang != "en" {
		t.Errorf("unexpected reverse params: region=%q lang=%q", seenReverseRegion, seenReverseLang)
	}
}

func TestGeoHandlers_MissingKeyReturns503(t *testing.T) {
	_, mux, _, cleanup := newGeoTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("upstream Google should not be called when key is missing")
	}, "")
	defer cleanup()

	token := makeGeoJWT(t, "cust-503", "user")
	for _, path := range []string{
		"/users/geo/autocomplete?q=cairo",
		"/users/geo/place?place_id=ChIJ_1",
		"/users/geo/reverse?lat=30.04&lng=31.23",
	} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusServiceUnavailable {
			t.Errorf("%s: status = %d, want 503", path, rec.Code)
		}
		var body map[string]string
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		if body["code"] != "geo_unavailable" {
			t.Errorf("%s: code = %q, want geo_unavailable", path, body["code"])
		}
	}
}

func TestGeoHandlers_UpstreamErrorsReturnStableCodes(t *testing.T) {
	_, mux, _, cleanup := newGeoTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/v1/places:autocomplete":
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":{"message":"API key test-google-server-key invalid raw detail"}}`))
		case strings.HasPrefix(r.URL.Path, "/v1/places/"):
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":{"message":"raw google not found"}}`))
		case r.URL.Path == "/maps/api/geocode/json":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"status":        "OVER_QUERY_LIMIT",
				"error_message": "raw google quota exceeded",
			})
		}
	}, "test-google-server-key")
	defer cleanup()

	token := makeGeoJWT(t, "cust-err", "user")

	// Autocomplete upstream error -> 502 geo_upstream_error, raw Google text never leaked
	req1 := httptest.NewRequest(http.MethodGet, "/users/geo/autocomplete?q=cairo", nil)
	req1.Header.Set("Authorization", "Bearer "+token)
	rec1 := httptest.NewRecorder()
	mux.ServeHTTP(rec1, req1)
	if rec1.Code != http.StatusBadGateway {
		t.Fatalf("autocomplete err status = %d, want 502", rec1.Code)
	}
	if strings.Contains(rec1.Body.String(), "raw detail") || strings.Contains(rec1.Body.String(), "test-google-server-key") {
		t.Fatalf("response leaked Google raw error/key: %s", rec1.Body.String())
	}
	var body1 map[string]string
	_ = json.Unmarshal(rec1.Body.Bytes(), &body1)
	if body1["code"] != "geo_upstream_error" {
		t.Errorf("code = %q, want geo_upstream_error", body1["code"])
	}

	// Place 404 -> 404 geo_place_not_found
	req2 := httptest.NewRequest(http.MethodGet, "/users/geo/place?place_id=missing", nil)
	req2.Header.Set("Authorization", "Bearer "+token)
	rec2 := httptest.NewRecorder()
	mux.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusNotFound {
		t.Fatalf("place 404 status = %d, want 404", rec2.Code)
	}
	var body2 map[string]string
	_ = json.Unmarshal(rec2.Body.Bytes(), &body2)
	if body2["code"] != "geo_place_not_found" {
		t.Errorf("code = %q, want geo_place_not_found", body2["code"])
	}

	// Reverse OVER_QUERY_LIMIT -> 429 geo_rate_limited
	req3 := httptest.NewRequest(http.MethodGet, "/users/geo/reverse?lat=30.0&lng=31.0", nil)
	req3.Header.Set("Authorization", "Bearer "+token)
	rec3 := httptest.NewRecorder()
	mux.ServeHTTP(rec3, req3)
	if rec3.Code != http.StatusTooManyRequests {
		t.Fatalf("reverse quota status = %d, want 429", rec3.Code)
	}
	if strings.Contains(rec3.Body.String(), "raw google quota exceeded") {
		t.Fatalf("response leaked raw Google error: %s", rec3.Body.String())
	}
	var body3 map[string]string
	_ = json.Unmarshal(rec3.Body.Bytes(), &body3)
	if body3["code"] != "geo_rate_limited" {
		t.Errorf("code = %q, want geo_rate_limited", body3["code"])
	}
}

func TestGeoHandlers_IdenticalCallsReachUpstreamTwice(t *testing.T) {
	var placeCalls atomic.Int32
	var reverseCalls atomic.Int32

	_, mux, _, cleanup := newGeoTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasPrefix(r.URL.Path, "/v1/places/"):
			placeCalls.Add(1)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"shortFormattedAddress": "Tahrir Sq",
				"location":              map[string]any{"latitude": 30.0444, "longitude": 31.2357},
			})
		case r.URL.Path == "/maps/api/geocode/json":
			reverseCalls.Add(1)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"status": "OK",
				"results": []map[string]any{
					{"formatted_address": "Tahrir Sq, Cairo"},
				},
			})
		}
	}, "test-key")
	defer cleanup()

	token := makeGeoJWT(t, "cust-nocache", "user")

	// Two identical place requests both reach Google (no server-side address cache).
	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodGet, "/users/geo/place?place_id=ChIJ_same&session=s1", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("place %d status = %d", i, rec.Code)
		}
	}
	if placeCalls.Load() != 2 {
		t.Errorf("placeCalls = %d, want 2", placeCalls.Load())
	}

	// Two identical reverse requests both reach Google (no server-side address cache).
	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodGet, "/users/geo/reverse?lat=30.0444&lng=31.2357", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("reverse %d status = %d", i, rec.Code)
		}
	}
	if reverseCalls.Load() != 2 {
		t.Errorf("reverseCalls = %d, want 2", reverseCalls.Load())
	}
}

func TestGeoHandlers_RateLimitPerUser(t *testing.T) {
	_, mux, _, cleanup := newGeoTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/v1/places:autocomplete":
			_ = json.NewEncoder(w).Encode(map[string]any{"suggestions": []any{}})
		case strings.HasPrefix(r.URL.Path, "/v1/places/"):
			_ = json.NewEncoder(w).Encode(map[string]any{
				"shortFormattedAddress": "Addr",
				"location":              map[string]any{"latitude": 30.0, "longitude": 31.0},
			})
		case r.URL.Path == "/maps/api/geocode/json":
			_ = json.NewEncoder(w).Encode(map[string]any{"status": "ZERO_RESULTS"})
		}
	}, "test-key")
	defer cleanup()

	userA := makeGeoJWT(t, "user-rl-a", "user")
	userB := makeGeoJWT(t, "user-rl-b", "user")

	// Autocomplete: 30/min per user
	for i := 0; i < geoAutocompleteLimitPerMin; i++ {
		req := httptest.NewRequest(http.MethodGet, "/users/geo/autocomplete?q=cairo", nil)
		req.Header.Set("Authorization", "Bearer "+userA)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("autocomplete call %d got %d, want 200", i+1, rec.Code)
		}
	}
	reqOverAC := httptest.NewRequest(http.MethodGet, "/users/geo/autocomplete?q=cairo", nil)
	reqOverAC.Header.Set("Authorization", "Bearer "+userA)
	recOverAC := httptest.NewRecorder()
	mux.ServeHTTP(recOverAC, reqOverAC)
	if recOverAC.Code != http.StatusTooManyRequests {
		t.Fatalf("autocomplete over limit got %d, want 429", recOverAC.Code)
	}
	// User B is unaffected
	reqOtherAC := httptest.NewRequest(http.MethodGet, "/users/geo/autocomplete?q=cairo", nil)
	reqOtherAC.Header.Set("Authorization", "Bearer "+userB)
	recOtherAC := httptest.NewRecorder()
	mux.ServeHTTP(recOtherAC, reqOtherAC)
	if recOtherAC.Code != http.StatusOK {
		t.Fatalf("other user autocomplete got %d, want 200", recOtherAC.Code)
	}

	// Place: 20/min per user
	for i := 0; i < geoPlaceLimitPerMin; i++ {
		req := httptest.NewRequest(http.MethodGet, "/users/geo/place?place_id=ChIJ_1", nil)
		req.Header.Set("Authorization", "Bearer "+userA)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("place call %d got %d, want 200", i+1, rec.Code)
		}
	}
	reqOverPlace := httptest.NewRequest(http.MethodGet, "/users/geo/place?place_id=ChIJ_1", nil)
	reqOverPlace.Header.Set("Authorization", "Bearer "+userA)
	recOverPlace := httptest.NewRecorder()
	mux.ServeHTTP(recOverPlace, reqOverPlace)
	if recOverPlace.Code != http.StatusTooManyRequests {
		t.Fatalf("place over limit got %d, want 429", recOverPlace.Code)
	}

	// Reverse: 30/min per user
	for i := 0; i < geoReverseLimitPerMin; i++ {
		req := httptest.NewRequest(http.MethodGet, "/users/geo/reverse?lat=30.0444&lng=31.2357", nil)
		req.Header.Set("Authorization", "Bearer "+userA)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("reverse call %d got %d, want 200", i+1, rec.Code)
		}
	}
	reqOverRev := httptest.NewRequest(http.MethodGet, "/users/geo/reverse?lat=30.0444&lng=31.2357", nil)
	reqOverRev.Header.Set("Authorization", "Bearer "+userA)
	recOverRev := httptest.NewRecorder()
	mux.ServeHTTP(recOverRev, reqOverRev)
	if recOverRev.Code != http.StatusTooManyRequests {
		t.Fatalf("reverse over limit got %d, want 429", recOverRev.Code)
	}
}

func TestGeoHandlers_AuthAndValidationTable(t *testing.T) {
	_, mux, _, cleanup := newGeoTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/v1/places:autocomplete":
			_ = json.NewEncoder(w).Encode(map[string]any{"suggestions": []any{}})
		case strings.HasPrefix(r.URL.Path, "/v1/places/"):
			_ = json.NewEncoder(w).Encode(map[string]any{
				"shortFormattedAddress": "Addr",
				"location":              map[string]any{"latitude": 30.0, "longitude": 31.0},
			})
		case r.URL.Path == "/maps/api/geocode/json":
			_ = json.NewEncoder(w).Encode(map[string]any{"status": "ZERO_RESULTS"})
		}
	}, "test-key")
	defer cleanup()

	// Unauthenticated -> 401
	for _, path := range []string{
		"/users/geo/autocomplete?q=cairo",
		"/users/geo/place?place_id=ChIJ_1",
		"/users/geo/reverse?lat=30.0&lng=31.0",
	} {
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("unauthenticated %s: status=%d, want 401", path, rec.Code)
		}
	}

	// Wrong method -> 405
	token := makeGeoJWT(t, "cust-val", "user")
	reqPost := httptest.NewRequest(http.MethodPost, "/users/geo/autocomplete?q=cairo", nil)
	reqPost.Header.Set("Authorization", "Bearer "+token)
	recPost := httptest.NewRecorder()
	mux.ServeHTTP(recPost, reqPost)
	if recPost.Code != http.StatusMethodNotAllowed {
		t.Errorf("POST status=%d, want 405", recPost.Code)
	}

	cases := []struct {
		name     string
		path     string
		wantCode int
		wantErr  string
	}{
		{"q empty", "/users/geo/autocomplete", http.StatusBadRequest, "invalid_query"},
		{"q spaces only", "/users/geo/autocomplete?q=%20%20%20", http.StatusBadRequest, "invalid_query"},
		{"q 2 runes after trim", "/users/geo/autocomplete?q=%20ab%20", http.StatusBadRequest, "invalid_query"},
		{"q 2 arabic runes", "/users/geo/autocomplete?q=" + url.QueryEscape("أب"), http.StatusBadRequest, "invalid_query"},
		{"q 3 arabic runes ok", "/users/geo/autocomplete?q=" + url.QueryEscape("مصر"), http.StatusOK, ""},
		{"q 101 runes", "/users/geo/autocomplete?q=" + strings.Repeat("أ", 101), http.StatusBadRequest, "invalid_query"},
		{"session 65 chars", "/users/geo/autocomplete?q=cairo&session=" + strings.Repeat("a", 65), http.StatusBadRequest, "invalid_session"},
		{"session with space", "/users/geo/autocomplete?q=cairo&session=ab%20cd", http.StatusBadRequest, "invalid_session"},
		{"place_id empty", "/users/geo/place", http.StatusBadRequest, "invalid_place_id"},
		{"place_id slash", "/users/geo/place?place_id=a/b", http.StatusBadRequest, "invalid_place_id"},
		{"place_id >300", "/users/geo/place?place_id=" + strings.Repeat("x", 301), http.StatusBadRequest, "invalid_place_id"},
		{"place session >64", "/users/geo/place?place_id=ChIJ_1&session=" + strings.Repeat("s", 65), http.StatusBadRequest, "invalid_session"},
		{"reverse missing lat", "/users/geo/reverse?lng=31.2", http.StatusBadRequest, "invalid_coordinates"},
		{"reverse missing lng", "/users/geo/reverse?lat=30.0", http.StatusBadRequest, "invalid_coordinates"},
		{"reverse lat > 90", "/users/geo/reverse?lat=90.1&lng=31.2", http.StatusBadRequest, "invalid_coordinates"},
		{"reverse lat < -90", "/users/geo/reverse?lat=-90.1&lng=31.2", http.StatusBadRequest, "invalid_coordinates"},
		{"reverse lng > 180", "/users/geo/reverse?lat=30.0&lng=180.1", http.StatusBadRequest, "invalid_coordinates"},
		{"reverse lng NaN", "/users/geo/reverse?lat=30.0&lng=NaN", http.StatusBadRequest, "invalid_coordinates"},
		{"reverse non-numeric", "/users/geo/reverse?lat=abc&lng=31.2", http.StatusBadRequest, "invalid_coordinates"},
		{"reverse valid edge", "/users/geo/reverse?lat=-90&lng=180", http.StatusOK, ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uTok := makeGeoJWT(t, "val-user-"+tc.name, "user")
			req := httptest.NewRequest(http.MethodGet, tc.path, nil)
			req.Header.Set("Authorization", "Bearer "+uTok)
			rec := httptest.NewRecorder()
			mux.ServeHTTP(rec, req)
			if rec.Code != tc.wantCode {
				t.Fatalf("%s: status = %d, want %d (body=%s)", tc.name, rec.Code, tc.wantCode, rec.Body.String())
			}
			if tc.wantErr != "" {
				var body map[string]string
				_ = json.Unmarshal(rec.Body.Bytes(), &body)
				if body["code"] != tc.wantErr {
					t.Errorf("%s: code = %q, want %q", tc.name, body["code"], tc.wantErr)
				}
			}
		})
	}
}
