package geo

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestClient_MissingKeyUnavailable(t *testing.T) {
	c := NewClient(Config{APIKey: ""})
	if c.Available() {
		t.Fatal("expected Available() == false with empty key")
	}
	if _, err := c.Autocomplete(context.Background(), "tahrir", "sess1", "en"); !errors.Is(err, ErrUnavailable) {
		t.Errorf("Autocomplete err = %v, want ErrUnavailable", err)
	}
	if _, err := c.PlaceDetails(context.Background(), "ChIJ1", "sess1", "en"); !errors.Is(err, ErrUnavailable) {
		t.Errorf("PlaceDetails err = %v, want ErrUnavailable", err)
	}
	if _, err := c.ReverseGeocode(context.Background(), 30.0444, 31.2357, "en"); !errors.Is(err, ErrUnavailable) {
		t.Errorf("ReverseGeocode err = %v, want ErrUnavailable", err)
	}
}

func TestNormalizeLang(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"", "en"},
		{"ar", "ar"},
		{"ar-EG,en;q=0.9", "ar"},
		{"AR_EG", "ar"},
		{"en-US,en;q=0.8", "en"},
		{"fr-FR", "en"},
		{"en,ar;q=0.5", "en"},
	}
	for _, tc := range cases {
		if got := NormalizeLang(tc.in); got != tc.want {
			t.Errorf("NormalizeLang(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestClient_Autocomplete_EgyptBiasAndCap5(t *testing.T) {
	var gotKey string
	var gotBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/places:autocomplete" || r.Method != http.MethodPost {
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		gotKey = r.Header.Get("X-Goog-Api-Key")
		if err := json.NewDecoder(r.Body).Decode(&gotBody); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		suggestions := make([]map[string]any, 0, 7)
		for i := 0; i < 7; i++ {
			suggestions = append(suggestions, map[string]any{
				"placePrediction": map[string]any{
					"placeId": "pid-" + string(rune('a'+i)),
					"structuredFormat": map[string]any{
						"mainText":      map[string]any{"text": "Street " + string(rune('A'+i))},
						"secondaryText": map[string]any{"text": "Cairo, Egypt"},
					},
				},
			})
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"suggestions": suggestions})
	}))
	defer srv.Close()

	c := NewClient(Config{
		APIKey:        "secret-server-key",
		PlacesBaseURL: srv.URL,
	})
	items, err := c.Autocomplete(context.Background(), "شارع التحرير", "sess-123", "ar-EG,en;q=0.8")
	if err != nil {
		t.Fatalf("Autocomplete failed: %v", err)
	}
	if gotKey != "secret-server-key" {
		t.Errorf("X-Goog-Api-Key = %q, want secret-server-key", gotKey)
	}
	if gotBody["regionCode"] != "eg" {
		t.Errorf("regionCode = %v, want eg", gotBody["regionCode"])
	}
	if gotBody["languageCode"] != "ar" {
		t.Errorf("languageCode = %v, want ar", gotBody["languageCode"])
	}
	if gotBody["sessionToken"] != "sess-123" {
		t.Errorf("sessionToken = %v, want sess-123", gotBody["sessionToken"])
	}
	regions, ok := gotBody["includedRegionCodes"].([]any)
	if !ok || len(regions) != 1 || regions[0] != "eg" {
		t.Errorf("includedRegionCodes = %v, want [eg]", gotBody["includedRegionCodes"])
	}
	if len(items) != 5 {
		t.Fatalf("expected 5 capped results, got %d", len(items))
	}
	if items[0].PlaceID != "pid-a" || items[0].Primary != "Street A" || items[0].Secondary != "Cairo, Egypt" {
		t.Errorf("unexpected first suggestion: %+v", items[0])
	}
}

func TestClient_PlaceDetails_CacheAndSession(t *testing.T) {
	var upstreamCalls atomic.Int32
	var lastSession, lastRegion, lastLang string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamCalls.Add(1)
		lastSession = r.URL.Query().Get("sessionToken")
		lastRegion = r.URL.Query().Get("regionCode")
		lastLang = r.URL.Query().Get("languageCode")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":                    "ChIJ_tahrir",
			"formattedAddress":      "15 Tahrir Sq, Abdeen, Cairo Governorate, Egypt",
			"shortFormattedAddress": "15 Tahrir Sq, Abdeen",
			"location": map[string]any{
				"latitude":  30.0444,
				"longitude": 31.2357,
			},
			"addressComponents": []map[string]any{
				{"longText": "Abdeen", "types": []string{"sublocality_level_1", "political"}},
			},
		})
	}))
	defer srv.Close()

	now := time.Date(2026, 11, 27, 10, 0, 0, 0, time.UTC)
	c := NewClient(Config{
		APIKey:        "secret-key",
		PlacesBaseURL: srv.URL,
		CacheTTL:      24 * time.Hour,
		Now:           func() time.Time { return now },
	})

	got1, err := c.PlaceDetails(context.Background(), "ChIJ_tahrir", "sess-xyz", "en")
	if err != nil {
		t.Fatalf("PlaceDetails 1 failed: %v", err)
	}
	if lastSession != "sess-xyz" || lastRegion != "eg" || lastLang != "en" {
		t.Errorf("unexpected query params: session=%q region=%q lang=%q", lastSession, lastRegion, lastLang)
	}
	if got1.Lat != 30.0444 || got1.Lng != 31.2357 || got1.Address != "15 Tahrir Sq, Abdeen" || got1.Area != "Abdeen" {
		t.Errorf("unexpected details: %+v", got1)
	}

	// Cache hit: same place_id and lang should not call upstream.
	got2, err := c.PlaceDetails(context.Background(), "ChIJ_tahrir", "sess-other", "en")
	if err != nil {
		t.Fatalf("PlaceDetails 2 failed: %v", err)
	}
	if got2 != got1 {
		t.Errorf("cached result mismatch: %+v != %+v", got2, got1)
	}
	if upstreamCalls.Load() != 1 {
		t.Errorf("upstream calls = %d, want 1", upstreamCalls.Load())
	}

	// After 24h TTL expires, calls upstream again.
	now = now.Add(25 * time.Hour)
	_, err = c.PlaceDetails(context.Background(), "ChIJ_tahrir", "sess-new", "en")
	if err != nil {
		t.Fatalf("PlaceDetails 3 failed: %v", err)
	}
	if upstreamCalls.Load() != 2 {
		t.Errorf("upstream calls after TTL = %d, want 2", upstreamCalls.Load())
	}
}

func TestClient_ReverseGeocode_RoundedCacheAndErrors(t *testing.T) {
	var upstreamCalls atomic.Int32
	var nextStatus = "OK"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamCalls.Add(1)
		if r.URL.Query().Get("region") != "eg" {
			t.Errorf("expected region=eg, got %q", r.URL.Query().Get("region"))
		}
		if nextStatus == "OVER_QUERY_LIMIT" {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"status":        "OVER_QUERY_LIMIT",
				"error_message": "raw secret quota text",
			})
			return
		}
		if nextStatus == "REQUEST_DENIED" {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"status":        "REQUEST_DENIED",
				"error_message": "The provided API key is invalid.",
			})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status": nextStatus,
			"results": []map[string]any{
				{
					"formatted_address": "15 Kasr El Nil, Qasr El Nil, Cairo",
					"address_components": []map[string]any{
						{"long_name": "Qasr El Nil", "types": []string{"administrative_area_level_2", "political"}},
					},
				},
			},
		})
	}))
	defer srv.Close()

	c := NewClient(Config{
		APIKey:         "super-secret-google-key",
		GeocodeBaseURL: srv.URL,
	})

	// 1. Happy path
	r1, err := c.ReverseGeocode(context.Background(), 30.04441, 31.23571, "en")
	if err != nil {
		t.Fatalf("ReverseGeocode 1 failed: %v", err)
	}
	if r1.Address != "15 Kasr El Nil, Qasr El Nil, Cairo" || r1.Area != "Qasr El Nil" {
		t.Errorf("unexpected reverse result: %+v", r1)
	}

	// 2. Within 4 decimal places -> cache hit (no second upstream call)
	r2, err := c.ReverseGeocode(context.Background(), 30.04444, 31.23574, "en")
	if err != nil {
		t.Fatalf("ReverseGeocode 2 failed: %v", err)
	}
	if r2 != r1 {
		t.Errorf("expected cached result %+v, got %+v", r1, r2)
	}
	if upstreamCalls.Load() != 1 {
		t.Errorf("upstreamCalls = %d, want 1", upstreamCalls.Load())
	}

	// 3. Different language hits upstream
	_, err = c.ReverseGeocode(context.Background(), 30.04441, 31.23571, "ar")
	if err != nil {
		t.Fatalf("ReverseGeocode ar failed: %v", err)
	}
	if upstreamCalls.Load() != 2 {
		t.Errorf("upstreamCalls after ar = %d, want 2", upstreamCalls.Load())
	}

	// 4. OVER_QUERY_LIMIT -> ErrRateLimited, never exposes raw Google error_message
	nextStatus = "OVER_QUERY_LIMIT"
	_, err = c.ReverseGeocode(context.Background(), 30.1111, 31.1111, "en")
	if !errors.Is(err, ErrRateLimited) {
		t.Errorf("expected ErrRateLimited, got %v", err)
	}
	if strings.Contains(err.Error(), "raw secret quota text") {
		t.Errorf("error leaked raw Google message: %v", err)
	}

	// 5. REQUEST_DENIED -> ErrUpstreamError, never leaks key or raw Google text
	nextStatus = "REQUEST_DENIED"
	_, err = c.ReverseGeocode(context.Background(), 30.2222, 31.2222, "en")
	if !errors.Is(err, ErrUpstreamError) {
		t.Errorf("expected ErrUpstreamError, got %v", err)
	}
	if strings.Contains(err.Error(), "super-secret-google-key") || strings.Contains(err.Error(), "API key is invalid") {
		t.Errorf("error leaked sensitive upstream detail: %v", err)
	}
}

func TestClient_RedactsKeyOnTransportError(t *testing.T) {
	c := NewClient(Config{
		APIKey:         "AIzaSySecretKeyNeverLeak",
		GeocodeBaseURL: "http://127.0.0.1:1", // closed port
		HTTPClient:     &http.Client{Timeout: 500 * time.Millisecond},
	})
	_, err := c.ReverseGeocode(context.Background(), 30.0444, 31.2357, "en")
	if err == nil {
		t.Fatal("expected error for closed port")
	}
	if strings.Contains(err.Error(), "AIzaSySecretKeyNeverLeak") {
		t.Fatalf("transport error leaked API key: %v", err)
	}
}

func TestCache_BoundedEviction(t *testing.T) {
	cache := newTTLCache[int](2, time.Hour, nil)
	cache.Set("a", 1)
	cache.Set("b", 2)
	// Touch "a" so "b" becomes LRU
	if v, ok := cache.Get("a"); !ok || v != 1 {
		t.Fatalf("expected cache hit for a")
	}
	cache.Set("c", 3)
	if cache.Len() != 2 {
		t.Fatalf("expected bounded Len=2, got %d", cache.Len())
	}
	if _, ok := cache.Get("b"); ok {
		t.Errorf("expected LRU key b to be evicted")
	}
	if _, ok := cache.Get("a"); !ok {
		t.Errorf("expected MRU key a to remain")
	}
	if _, ok := cache.Get("c"); !ok {
		t.Errorf("expected c to remain")
	}
}
