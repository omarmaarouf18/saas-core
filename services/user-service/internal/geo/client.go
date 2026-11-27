// Package geo provides a reusable, cost-controlled Google Maps Platform HTTP
// client (Places API New, Geocoding API, and future Routes API) for user-service.
package geo

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode"
)

const (
	DefaultPlacesBaseURL  = "https://places.googleapis.com"
	DefaultGeocodeBaseURL = "https://maps.googleapis.com"
	DefaultRoutesBaseURL  = "https://routes.googleapis.com"

	DefaultCacheTTL        = 24 * time.Hour
	DefaultMaxCacheEntries = 5000
	DefaultHTTPTimeout     = 5 * time.Second

	maxAutocompleteResults = 5
	maxAddressRunes        = 250
	maxAreaRunes           = 100
	maxSuggestionTextRunes = 200
	maxResponseBytes       = 1 << 20 // 1 MiB
)

var (
	// ErrUnavailable indicates that GOOGLE_MAPS_SERVER_KEY is not configured.
	ErrUnavailable = errors.New("geo_unavailable")
	// ErrRateLimited indicates that Google rejected the request due to quota/rate limits.
	ErrRateLimited = errors.New("geo_rate_limited")
	// ErrUpstreamError indicates an upstream Google transport or API error.
	ErrUpstreamError = errors.New("geo_upstream_error")
	// ErrNotFound indicates the requested place_id was not found upstream.
	ErrNotFound = errors.New("geo_place_not_found")
)

// Config configures the Google Maps Platform client.
type Config struct {
	APIKey          string
	PlacesBaseURL   string
	GeocodeBaseURL  string
	RoutesBaseURL   string
	HTTPClient      *http.Client
	CacheTTL        time.Duration
	MaxCacheEntries int
	Now             func() time.Time
}

// Suggestion represents a single address autocomplete suggestion.
type Suggestion struct {
	PlaceID   string `json:"place_id"`
	Primary   string `json:"primary"`
	Secondary string `json:"secondary"`
}

// PlaceDetails represents resolved coordinates and address text for a place_id.
type PlaceDetails struct {
	Lat     float64 `json:"lat"`
	Lng     float64 `json:"lng"`
	Address string  `json:"address"`
	Area    string  `json:"area"`
}

// ReverseResult represents reverse-geocoded address text for coordinates.
type ReverseResult struct {
	Address string `json:"address"`
	Area    string `json:"area"`
}

// Client wraps Google Maps Platform HTTP endpoints with Egypt biasing,
// key redaction, stable error mapping, and bounded in-memory caching.
type Client struct {
	apiKey         string
	placesBaseURL  string
	geocodeBaseURL string
	routesBaseURL  string
	httpClient     *http.Client
	placeCache     *ttlCache[PlaceDetails]
	reverseCache   *ttlCache[ReverseResult]
}

// NewClient creates a new Google Maps Platform client. If APIKey is empty,
// Available returns false and all calls return ErrUnavailable.
func NewClient(cfg Config) *Client {
	placesURL := strings.TrimRight(strings.TrimSpace(cfg.PlacesBaseURL), "/")
	if placesURL == "" {
		placesURL = DefaultPlacesBaseURL
	}
	geocodeURL := strings.TrimRight(strings.TrimSpace(cfg.GeocodeBaseURL), "/")
	if geocodeURL == "" {
		geocodeURL = DefaultGeocodeBaseURL
	}
	routesURL := strings.TrimRight(strings.TrimSpace(cfg.RoutesBaseURL), "/")
	if routesURL == "" {
		routesURL = DefaultRoutesBaseURL
	}
	httpClient := cfg.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{Timeout: DefaultHTTPTimeout}
	}
	ttl := cfg.CacheTTL
	if ttl <= 0 {
		ttl = DefaultCacheTTL
	}
	maxEntries := cfg.MaxCacheEntries
	if maxEntries <= 0 {
		maxEntries = DefaultMaxCacheEntries
	}

	return &Client{
		apiKey:         strings.TrimSpace(cfg.APIKey),
		placesBaseURL:  placesURL,
		geocodeBaseURL: geocodeURL,
		routesBaseURL:  routesURL,
		httpClient:     httpClient,
		placeCache:     newTTLCache[PlaceDetails](maxEntries, ttl, cfg.Now),
		reverseCache:   newTTLCache[ReverseResult](maxEntries, ttl, cfg.Now),
	}
}

// Available reports whether the server API key is configured.
func (c *Client) Available() bool {
	return c != nil && c.apiKey != ""
}

// NormalizeLang normalizes Accept-Language into "ar" or "en" (default "en").
func NormalizeLang(acceptLanguage string) string {
	for _, part := range strings.Split(acceptLanguage, ",") {
		tag := strings.TrimSpace(strings.SplitN(part, ";", 2)[0])
		if tag == "" {
			continue
		}
		lower := strings.ToLower(tag)
		if lower == "ar" || strings.HasPrefix(lower, "ar-") || strings.HasPrefix(lower, "ar_") {
			return "ar"
		}
		if lower == "en" || strings.HasPrefix(lower, "en-") || strings.HasPrefix(lower, "en_") {
			return "en"
		}
	}
	return "en"
}

// RoundCoord4 rounds a coordinate to 4 decimal places (~11 m precision) and
// normalizes -0.0 to 0.0 for deterministic cache keys.
func RoundCoord4(v float64) float64 {
	r := math.Round(v*10000) / 10000
	if r == 0 {
		return 0
	}
	return r
}

// RoutesBaseURL returns the configured Routes API base URL for future route calls.
func (c *Client) RoutesBaseURL() string {
	if c == nil {
		return DefaultRoutesBaseURL
	}
	return c.routesBaseURL
}

// Autocomplete queries Google Places API (New) autocomplete biased to Egypt.
func (c *Client) Autocomplete(ctx context.Context, query, session, lang string) ([]Suggestion, error) {
	if !c.Available() {
		return nil, ErrUnavailable
	}

	reqBody := struct {
		Input               string   `json:"input"`
		SessionToken        string   `json:"sessionToken,omitempty"`
		IncludedRegionCodes []string `json:"includedRegionCodes"`
		RegionCode          string   `json:"regionCode"`
		LanguageCode        string   `json:"languageCode"`
	}{
		Input:               query,
		SessionToken:        session,
		IncludedRegionCodes: []string{"eg"},
		RegionCode:          "eg",
		LanguageCode:        NormalizeLang(lang),
	}

	headers := map[string]string{
		"Content-Type":     "application/json",
		"X-Goog-Api-Key":   c.apiKey,
		"X-Goog-FieldMask": "suggestions.placePrediction.placeId,suggestions.placePrediction.structuredFormat.mainText.text,suggestions.placePrediction.structuredFormat.secondaryText.text,suggestions.placePrediction.text.text",
	}

	var resp struct {
		Suggestions []struct {
			PlacePrediction *struct {
				PlaceID string `json:"placeId"`
				Text    *struct {
					Text string `json:"text"`
				} `json:"text"`
				StructuredFormat *struct {
					MainText *struct {
						Text string `json:"text"`
					} `json:"mainText"`
					SecondaryText *struct {
						Text string `json:"text"`
					} `json:"secondaryText"`
				} `json:"structuredFormat"`
			} `json:"placePrediction"`
		} `json:"suggestions"`
	}

	endpoint := c.placesBaseURL + "/v1/places:autocomplete"
	if err := c.doJSON(ctx, http.MethodPost, endpoint, headers, reqBody, &resp); err != nil {
		return nil, err
	}

	out := make([]Suggestion, 0, maxAutocompleteResults)
	for _, s := range resp.Suggestions {
		if s.PlacePrediction == nil || strings.TrimSpace(s.PlacePrediction.PlaceID) == "" {
			continue
		}
		p := s.PlacePrediction
		var primary, secondary string
		if p.StructuredFormat != nil {
			if p.StructuredFormat.MainText != nil {
				primary = p.StructuredFormat.MainText.Text
			}
			if p.StructuredFormat.SecondaryText != nil {
				secondary = p.StructuredFormat.SecondaryText.Text
			}
		}
		if strings.TrimSpace(primary) == "" && p.Text != nil {
			primary = p.Text.Text
		}
		primary = sanitizeAndCap(primary, maxSuggestionTextRunes)
		secondary = sanitizeAndCap(secondary, maxSuggestionTextRunes)
		if primary == "" {
			continue
		}
		out = append(out, Suggestion{
			PlaceID:   strings.TrimSpace(p.PlaceID),
			Primary:   primary,
			Secondary: secondary,
		})
		if len(out) >= maxAutocompleteResults {
			break
		}
	}
	return out, nil
}

// PlaceDetails resolves coordinates and address details for placeID via Places API (New),
// completing any active autocomplete session token. Results are cached in memory for 24h.
func (c *Client) PlaceDetails(ctx context.Context, placeID, session, lang string) (PlaceDetails, error) {
	if !c.Available() {
		return PlaceDetails{}, ErrUnavailable
	}

	normLang := NormalizeLang(lang)
	cacheKey := placeID + "|" + normLang
	if cached, ok := c.placeCache.Get(cacheKey); ok {
		return cached, nil
	}

	params := url.Values{}
	params.Set("regionCode", "eg")
	params.Set("languageCode", normLang)
	if session != "" {
		params.Set("sessionToken", session)
	}
	endpoint := fmt.Sprintf("%s/v1/places/%s?%s", c.placesBaseURL, url.PathEscape(placeID), params.Encode())

	headers := map[string]string{
		"X-Goog-Api-Key":   c.apiKey,
		"X-Goog-FieldMask": "id,formattedAddress,shortFormattedAddress,location,addressComponents",
	}

	var resp struct {
		FormattedAddress      string `json:"formattedAddress"`
		ShortFormattedAddress string `json:"shortFormattedAddress"`
		Location              *struct {
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
		} `json:"location"`
		AddressComponents []struct {
			LongText  string   `json:"longText"`
			ShortText string   `json:"shortText"`
			Types     []string `json:"types"`
		} `json:"addressComponents"`
	}

	if err := c.doJSON(ctx, http.MethodGet, endpoint, headers, nil, &resp); err != nil {
		return PlaceDetails{}, err
	}

	if resp.Location == nil ||
		math.IsNaN(resp.Location.Latitude) || math.IsInf(resp.Location.Latitude, 0) ||
		math.IsNaN(resp.Location.Longitude) || math.IsInf(resp.Location.Longitude, 0) {
		return PlaceDetails{}, fmt.Errorf("%w: missing location", ErrUpstreamError)
	}

	addr := resp.ShortFormattedAddress
	if strings.TrimSpace(addr) == "" {
		addr = resp.FormattedAddress
	}
	comps := make([]addressComponent, 0, len(resp.AddressComponents))
	for _, ac := range resp.AddressComponents {
		comps = append(comps, addressComponent{
			name:  ac.LongText,
			types: ac.Types,
		})
	}

	details := PlaceDetails{
		Lat:     resp.Location.Latitude,
		Lng:     resp.Location.Longitude,
		Address: sanitizeAndCap(addr, maxAddressRunes),
		Area:    sanitizeAndCap(extractArea(comps), maxAreaRunes),
	}
	c.placeCache.Set(cacheKey, details)
	return details, nil
}

// ReverseGeocode resolves human-readable address text for (lat, lng) via Google Geocoding API
// with Egypt region bias. Results are cached in memory by coordinates rounded to 4 decimal places.
func (c *Client) ReverseGeocode(ctx context.Context, lat, lng float64, lang string) (ReverseResult, error) {
	if !c.Available() {
		return ReverseResult{}, ErrUnavailable
	}

	normLang := NormalizeLang(lang)
	rLat := RoundCoord4(lat)
	rLng := RoundCoord4(lng)
	cacheKey := fmt.Sprintf("%.4f,%.4f|%s", rLat, rLng, normLang)
	if cached, ok := c.reverseCache.Get(cacheKey); ok {
		return cached, nil
	}

	params := url.Values{}
	params.Set("latlng", fmt.Sprintf("%.6f,%.6f", lat, lng))
	params.Set("region", "eg")
	params.Set("language", normLang)
	params.Set("key", c.apiKey)
	endpoint := fmt.Sprintf("%s/maps/api/geocode/json?%s", c.geocodeBaseURL, params.Encode())

	var resp struct {
		Status  string `json:"status"`
		Results []struct {
			FormattedAddress  string `json:"formatted_address"`
			AddressComponents []struct {
				LongName  string   `json:"long_name"`
				ShortName string   `json:"short_name"`
				Types     []string `json:"types"`
			} `json:"address_components"`
		} `json:"results"`
	}

	if err := c.doJSON(ctx, http.MethodGet, endpoint, nil, nil, &resp); err != nil {
		return ReverseResult{}, err
	}

	switch resp.Status {
	case "OK":
		if len(resp.Results) == 0 {
			res := ReverseResult{}
			c.reverseCache.Set(cacheKey, res)
			return res, nil
		}
		first := resp.Results[0]
		comps := make([]addressComponent, 0, len(first.AddressComponents))
		for _, ac := range first.AddressComponents {
			comps = append(comps, addressComponent{
				name:  ac.LongName,
				types: ac.Types,
			})
		}
		res := ReverseResult{
			Address: sanitizeAndCap(first.FormattedAddress, maxAddressRunes),
			Area:    sanitizeAndCap(extractArea(comps), maxAreaRunes),
		}
		c.reverseCache.Set(cacheKey, res)
		return res, nil
	case "ZERO_RESULTS":
		res := ReverseResult{}
		c.reverseCache.Set(cacheKey, res)
		return res, nil
	case "OVER_QUERY_LIMIT":
		return ReverseResult{}, ErrRateLimited
	default:
		return ReverseResult{}, fmt.Errorf("%w: geocode status %s", ErrUpstreamError, resp.Status)
	}
}

// doJSON performs an HTTP request with optional JSON body, checks status codes,
// redacts any API key from transport errors, and decodes the JSON response.
func (c *Client) doJSON(ctx context.Context, method, endpoint string, headers map[string]string, reqBody any, respOut any) error {
	var bodyReader io.Reader
	if reqBody != nil {
		raw, err := json.Marshal(reqBody)
		if err != nil {
			return fmt.Errorf("%w: encode failed", ErrUpstreamError)
		}
		bodyReader = bytes.NewReader(raw)
	}

	req, err := http.NewRequestWithContext(ctx, method, endpoint, bodyReader)
	if err != nil {
		return fmt.Errorf("%w: %s", ErrUpstreamError, c.redactString(err.Error()))
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}

	// #nosec G704 //nolint:gosec -- endpoint uses configured Google Maps Platform base URL and validated/escaped parameters
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("%w: transport failure: %s", ErrUpstreamError, c.redactString(err.Error()))
	}
	defer resp.Body.Close()

	limitedBody, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))
	if err != nil {
		return fmt.Errorf("%w: read failure", ErrUpstreamError)
	}

	if resp.StatusCode == http.StatusTooManyRequests {
		return ErrRateLimited
	}
	if resp.StatusCode == http.StatusNotFound {
		return ErrNotFound
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("%w: upstream status %d", ErrUpstreamError, resp.StatusCode)
	}

	if respOut != nil {
		if err := json.Unmarshal(limitedBody, respOut); err != nil {
			return fmt.Errorf("%w: invalid upstream json", ErrUpstreamError)
		}
	}
	return nil
}

func (c *Client) redactString(s string) string {
	if c == nil || c.apiKey == "" {
		return s
	}
	return strings.ReplaceAll(s, c.apiKey, "[REDACTED]")
}

type addressComponent struct {
	name  string
	types []string
}

var areaTypePriority = []string{
	"sublocality_level_1",
	"sublocality",
	"neighborhood",
	"administrative_area_level_2",
	"locality",
	"administrative_area_level_1",
}

func extractArea(comps []addressComponent) string {
	for _, want := range areaTypePriority {
		for _, comp := range comps {
			for _, t := range comp.types {
				if t == want && strings.TrimSpace(comp.name) != "" {
					return comp.name
				}
			}
		}
	}
	return ""
}

func sanitizeAndCap(s string, maxRunes int) string {
	var b strings.Builder
	b.Grow(len(s))
	lastSpace := false
	for _, r := range strings.TrimSpace(s) {
		if unicode.IsControl(r) {
			if r == '\n' || r == '\r' || r == '\t' {
				if !lastSpace && b.Len() > 0 {
					b.WriteByte(' ')
					lastSpace = true
				}
			}
			continue
		}
		if r == ' ' {
			if lastSpace {
				continue
			}
			lastSpace = true
		} else {
			lastSpace = false
		}
		b.WriteRune(r)
	}
	cleaned := strings.TrimSpace(b.String())
	if maxRunes <= 0 {
		return cleaned
	}
	runes := []rune(cleaned)
	if len(runes) <= maxRunes {
		return cleaned
	}
	return strings.TrimSpace(string(runes[:maxRunes]))
}
