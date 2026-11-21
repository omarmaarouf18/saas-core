package handlers

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/redact"
)

// maxDeviceTokenLength bounds the device token accepted by the internal
// unregister endpoint. FCM/APNs registration tokens are far shorter, so an
// oversized value is a malformed request, not a real token.
const maxDeviceTokenLength = 512

// maxDeviceTokenUnregisterBodyBytes bounds the internal unregister request
// body before it is decoded. The body is {"token": "<at most 512 chars>"}, so
// 4 KiB is ample; a larger body is malformed or abusive and is rejected with
// 413 instead of being read into memory.
const maxDeviceTokenUnregisterBodyBytes = 4 << 10

// DeviceTokenUnregisterRequest is the body of the internal unregister call.
type DeviceTokenUnregisterRequest struct {
	Token string `json:"token"`
}

// DeviceTokenUnregisterStore is the narrow store capability the internal
// device-token endpoint needs. It is an interface (and not the concrete
// MongoDB store) so the endpoint can be exercised without a database.
type DeviceTokenUnregisterStore interface {
	// RemoveDeviceTokenFromAnyUser removes the token from every user record
	// that holds it and returns the number of changed user records.
	RemoveDeviceTokenFromAnyUser(ctx context.Context, token string) (int64, error)
}

// UnregisterStaleDeviceToken removes a stale push device token from every
// user that still holds it.
//
// POST /auth/internal/device-token/unregister
// Accepts: { "token": "..." }
//
// The caller is another backend service, not an end user: it authenticates
// with the X-Internal-Token header (constant-time comparison, like the other
// /auth/internal/* endpoints). The call is idempotent — a token nobody holds
// any more still answers 204 — and the token itself is never logged in full.
func (a *Auth) UnregisterStaleDeviceToken(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	internalToken := r.Header.Get("X-Internal-Token")
	if a.internalServiceToken == "" || subtle.ConstantTimeCompare([]byte(internalToken), []byte(a.internalServiceToken)) != 1 {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "unauthorized internal token",
		})
		return
	}

	// Bound the body only after the method and internal-token checks so an
	// unauthenticated caller still gets 401 without any body being read.
	r.Body = http.MaxBytesReader(w, r.Body, maxDeviceTokenUnregisterBodyBytes)
	var req DeviceTokenUnregisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			writeJSON(w, http.StatusRequestEntityTooLarge, map[string]string{
				"error": "request body too large",
			})
			return
		}
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid request body",
		})
		return
	}

	token := strings.TrimSpace(req.Token)
	if token == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "token is required",
		})
		return
	}
	if len(token) > maxDeviceTokenLength {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": fmt.Sprintf("token cannot exceed %d characters", maxDeviceTokenLength),
		})
		return
	}

	if a.deviceTokenStore == nil {
		log.Printf("[AUTH] Device-token unregister unavailable: the user store is not configured")
		handlerutil.WriteSafeError(w, r, http.StatusServiceUnavailable, handlerutil.ErrCodeUnavailable, "device token registry is unavailable", nil)
		return
	}

	removed, err := a.deviceTokenStore.RemoveDeviceTokenFromAnyUser(r.Context(), token)
	if err != nil {
		// The token is only ever logged as a short preview.
		log.Printf("[AUTH] Failed to unregister stale device token %s: %v", redact.PreviewToken(token), err)
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to unregister device token", err)
		return
	}

	log.Printf("[AUTH] Unregistered stale device token %s (user records changed: %d)", redact.PreviewToken(token), removed)
	w.WriteHeader(http.StatusNoContent)
}
