package handlers

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/geo"
	"github.com/redis/go-redis/v9"
)

const (
	errCodeGeoUnavailable       = "geo_unavailable"
	errCodeGeoUpstreamError     = "geo_upstream_error"
	errCodeGeoRateLimited       = "geo_rate_limited"
	errCodeGeoPlaceNotFound     = "geo_place_not_found"
	errCodeGeoInvalidQuery      = "invalid_query"
	errCodeGeoInvalidSession    = "invalid_session"
	errCodeGeoInvalidPlaceID    = "invalid_place_id"
	errCodeGeoInvalidCoords     = "invalid_coordinates"
	errCodeGeoRateLimitedClient = "rate_limited"

	geoAutocompleteLimitPerMin = 30
	geoPlaceLimitPerMin        = 20
	geoReverseLimitPerMin      = 30

	geoQueryMinRunes   = 3
	geoQueryMaxRunes   = 100
	geoSessionMaxRunes = 64
	geoPlaceIDMaxRunes = 300
)

type geoState struct {
	client              *geo.Client
	autocompleteLimiter *handlerutil.RateLimiter
	placeLimiter        *handlerutil.RateLimiter
	reverseLimiter      *handlerutil.RateLimiter
}

func newGeoState(cfg *config.Config, rdb *redis.Client) *geoState {
	var apiKey string
	if cfg != nil {
		apiKey = cfg.GoogleMapsServerKey
	}
	newLimiter := func(limit int, prefix string) *handlerutil.RateLimiter {
		if rdb == nil {
			return nil
		}
		return handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, limit, 1*time.Minute, prefix))
	}
	return &geoState{
		client:              geo.NewClient(geo.Config{APIKey: apiKey}),
		autocompleteLimiter: newLimiter(geoAutocompleteLimitPerMin, "user:geo_autocomplete"),
		placeLimiter:        newLimiter(geoPlaceLimitPerMin, "user:geo_place"),
		reverseLimiter:      newLimiter(geoReverseLimitPerMin, "user:geo_reverse"),
	}
}

// SetGeoClient overrides the Google Maps Platform client for testing.
func (u *UserService) SetGeoClient(client *geo.Client) {
	if u.geo == nil {
		u.geo = &geoState{}
	}
	u.geo.client = client
}

func extractBearerTokenOr401(w http.ResponseWriter, r *http.Request) (string, bool) {
	tokenStr := handlerutil.BearerToken(r)
	if tokenStr == "" {
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeUnauthorized, "authorization token required", nil)
		return "", false
	}
	return tokenStr, true
}

func validateGeoClaimsOr401(w http.ResponseWriter, r *http.Request, claims *jwtutil.Claims, err error) (string, bool) {
	if err != nil || claims == nil || strings.TrimSpace(claims.UserID) == "" {
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeInvalidToken, "invalid or expired token", err)
		return "", false
	}
	return claims.UserID, true
}

func (u *UserService) checkGeoAvailableAndLimit(w http.ResponseWriter, r *http.Request, userID string, limiter *handlerutil.RateLimiter) bool {
	if u.geo == nil || u.geo.client == nil || !u.geo.client.Available() {
		handlerutil.WriteSafeError(w, r, http.StatusServiceUnavailable, errCodeGeoUnavailable, "geo service unavailable", nil)
		return false
	}
	if limiter != nil {
		if limited, remaining := limiter.CheckAndRecord(userID); limited {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", math.Ceil(remaining.Seconds())),
				"code":  errCodeGeoRateLimitedClient,
			})
			return false
		}
	}
	return true
}

func validateSessionToken(session string) bool {
	if utf8.RuneCountInString(session) > geoSessionMaxRunes {
		return false
	}
	for _, r := range session {
		if unicode.IsControl(r) || unicode.IsSpace(r) {
			return false
		}
	}
	return true
}

func validatePlaceID(placeID string) bool {
	n := utf8.RuneCountInString(placeID)
	if n == 0 || n > geoPlaceIDMaxRunes {
		return false
	}
	for _, r := range placeID {
		if unicode.IsControl(r) || unicode.IsSpace(r) || r == '/' || r == '?' || r == '#' {
			return false
		}
	}
	return true
}

func writeGeoClientError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, geo.ErrUnavailable):
		handlerutil.WriteSafeError(w, r, http.StatusServiceUnavailable, errCodeGeoUnavailable, "geo service unavailable", err)
	case errors.Is(err, geo.ErrRateLimited):
		handlerutil.WriteSafeError(w, r, http.StatusTooManyRequests, errCodeGeoRateLimited, "geo service rate limited", err)
	case errors.Is(err, geo.ErrNotFound):
		handlerutil.WriteSafeError(w, r, http.StatusNotFound, errCodeGeoPlaceNotFound, "place not found", err)
	default:
		handlerutil.WriteSafeError(w, r, http.StatusBadGateway, errCodeGeoUpstreamError, "geo lookup failed", err)
	}
}

// GeoAutocomplete returns up to 5 Egypt-biased address suggestions from Google Places API (New).
func (u *UserService) GeoAutocomplete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	tokenStr, ok := extractBearerTokenOr401(w, r)
	if !ok {
		return
	}
	claims, err := jwtutil.ValidateToken(tokenStr)
	userID, ok := validateGeoClaimsOr401(w, r, claims, err)
	if !ok {
		return
	}
	var limiter *handlerutil.RateLimiter
	if u.geo != nil {
		limiter = u.geo.autocompleteLimiter
	}
	if !u.checkGeoAvailableAndLimit(w, r, userID, limiter) {
		return
	}

	q := strings.TrimSpace(r.URL.Query().Get("q"))
	qRunes := utf8.RuneCountInString(q)
	if qRunes < geoQueryMinRunes || qRunes > geoQueryMaxRunes {
		handlerutil.WriteSafeError(w, r, http.StatusBadRequest, errCodeGeoInvalidQuery, "q must be between 3 and 100 characters", nil)
		return
	}

	session := r.URL.Query().Get("session")
	if !validateSessionToken(session) {
		handlerutil.WriteSafeError(w, r, http.StatusBadRequest, errCodeGeoInvalidSession, "invalid session token", nil)
		return
	}

	lang := geo.NormalizeLang(r.Header.Get("Accept-Language"))
	suggestions, err := u.geo.client.Autocomplete(r.Context(), q, session, lang)
	if err != nil {
		writeGeoClientError(w, r, err)
		return
	}
	if suggestions == nil {
		suggestions = []geo.Suggestion{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"suggestions": suggestions,
	})
}

// GeoPlace resolves coordinates and address details for a Google place_id and closes the autocomplete session.
func (u *UserService) GeoPlace(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	tokenStr, ok := extractBearerTokenOr401(w, r)
	if !ok {
		return
	}
	claims, err := jwtutil.ValidateToken(tokenStr)
	userID, ok := validateGeoClaimsOr401(w, r, claims, err)
	if !ok {
		return
	}
	var limiter *handlerutil.RateLimiter
	if u.geo != nil {
		limiter = u.geo.placeLimiter
	}
	if !u.checkGeoAvailableAndLimit(w, r, userID, limiter) {
		return
	}

	placeID := strings.TrimSpace(r.URL.Query().Get("place_id"))
	if !validatePlaceID(placeID) {
		handlerutil.WriteSafeError(w, r, http.StatusBadRequest, errCodeGeoInvalidPlaceID, "invalid place_id", nil)
		return
	}

	session := r.URL.Query().Get("session")
	if !validateSessionToken(session) {
		handlerutil.WriteSafeError(w, r, http.StatusBadRequest, errCodeGeoInvalidSession, "invalid session token", nil)
		return
	}

	lang := geo.NormalizeLang(r.Header.Get("Accept-Language"))
	details, err := u.geo.client.PlaceDetails(r.Context(), placeID, session, lang)
	if err != nil {
		writeGeoClientError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, details)
}

// GeoReverse resolves a human-readable address and area from coordinates using Google Geocoding API.
func (u *UserService) GeoReverse(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	tokenStr, ok := extractBearerTokenOr401(w, r)
	if !ok {
		return
	}
	claims, err := jwtutil.ValidateToken(tokenStr)
	userID, ok := validateGeoClaimsOr401(w, r, claims, err)
	if !ok {
		return
	}
	var limiter *handlerutil.RateLimiter
	if u.geo != nil {
		limiter = u.geo.reverseLimiter
	}
	if !u.checkGeoAvailableAndLimit(w, r, userID, limiter) {
		return
	}

	latStr := strings.TrimSpace(r.URL.Query().Get("lat"))
	lngStr := strings.TrimSpace(r.URL.Query().Get("lng"))
	if latStr == "" || lngStr == "" {
		handlerutil.WriteSafeError(w, r, http.StatusBadRequest, errCodeGeoInvalidCoords, "lat and lng are required", nil)
		return
	}
	lat, err1 := strconv.ParseFloat(latStr, 64)
	lng, err2 := strconv.ParseFloat(lngStr, 64)
	if err1 != nil || err2 != nil ||
		math.IsNaN(lat) || math.IsInf(lat, 0) ||
		math.IsNaN(lng) || math.IsInf(lng, 0) ||
		lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		handlerutil.WriteSafeError(w, r, http.StatusBadRequest, errCodeGeoInvalidCoords, "lat/lng out of range", nil)
		return
	}

	lang := geo.NormalizeLang(r.Header.Get("Accept-Language"))
	res, err := u.geo.client.ReverseGeocode(r.Context(), lat, lng, lang)
	if err != nil {
		writeGeoClientError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}
