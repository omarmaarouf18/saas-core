// Package handlers implements HTTP handlers for the user-service.
package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

// UserService holds dependencies for the user-service handlers.
type UserService struct {
	store *store.Memory
}

// NewUserService creates a new handler group.
func NewUserService(s *store.Memory) *UserService {
	return &UserService{store: s}
}

// RegisterRoutes mounts all user-service endpoints on the given ServeMux.
// Paths include the /users/ prefix to align with the gateway's routing:
//
//	/api/v1/users/services → user-service → /users/services
//	/api/v1/users/jobs/track → user-service → /users/jobs/track
func (u *UserService) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/users/services", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			u.ListServices(w, r)
		case http.MethodPost:
			u.CreateService(w, r)
		default:
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
				"error": "method not allowed",
			})
		}
	})
	mux.HandleFunc("/users/jobs/track", u.TrackJob)
}

// ---------------------------------------------------------------------------
// GET /users/services?sort_by=price&near_by=true&lat=30.04&lon=31.23&radius=50
// ---------------------------------------------------------------------------

// ListServices returns available services with optional sorting and proximity filtering.
//
// Query parameters:
//   - sort_by:  "price" to sort ascending by base price (optional)
//   - near_by:  "true" to filter by proximity (optional)
//   - lat:      reference latitude  for near_by  (default: 30.0444)
//   - lon:      reference longitude for near_by  (default: 31.2357)
//   - radius:   max distance in km for near_by   (default: 50)
func (u *UserService) ListServices(w http.ResponseWriter, r *http.Request) {

	q := r.URL.Query()
	sortBy := q.Get("sort_by")
	nearBy := q.Get("near_by") == "true"

	// Default reference coordinates (Cairo, Egypt).
	refLat := parseFloat(q.Get("lat"), 30.0444)
	refLon := parseFloat(q.Get("lon"), 31.2357)
	radius := parseFloat(q.Get("radius"), 50)

	services := u.store.ListServices(sortBy, nearBy, refLat, refLon, radius)

	log.Printf("[USER] ListServices: sort_by=%s near_by=%v results=%d", sortBy, nearBy, len(services))

	writeJSON(w, http.StatusOK, map[string]any{
		"count":    len(services),
		"sort_by":  sortBy,
		"near_by":  nearBy,
		"services": services,
	})
}

// ---------------------------------------------------------------------------
// POST /users/services
// ---------------------------------------------------------------------------

// CreateService allows a tenant owner to register a new service.
func (u *UserService) CreateService(w http.ResponseWriter, r *http.Request) {
	var req models.CreateServiceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	if req.OwnerID == "" || req.Name == "" || req.Category == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "owner_id, name, and category are required",
		})
		return
	}

	// Strict enum validation
	if req.Category != "shipping" && req.Category != "delivery" && req.Category != "transport" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid category, must be one of: shipping, delivery, transport",
		})
		return
	}

	svc := &models.Service{
		ID:               generateID(),
		Name:             req.Name,
		Category:         req.Category,
		BasePrice:        req.TenantBasePrice, // Fallback if no specific base price was requested (or match tenant base)
		TenantBasePrice:  req.TenantBasePrice,
		TenantPricePerKM: req.TenantPricePerKM,
		Latitude:         req.Latitude,
		Longitude:        req.Longitude,
	}

	u.store.CreateService(svc)
	log.Printf("[USER] Service created: id=%s name=%s category=%s", svc.ID, svc.Name, svc.Category)

	writeJSON(w, http.StatusCreated, map[string]any{
		"message": "service created successfully",
		"service": svc,
	})
}

// ---------------------------------------------------------------------------
// POST /users/jobs/track
// ---------------------------------------------------------------------------

// TrackJob creates a new job tracking record and initialises its lifecycle.
//
// Accepts: { "owner_id", "service_id", "employee_id"?, "location": { "latitude", "longitude" } }
//
// The job is created with status "pending", then immediately progressed to
// "active" to simulate the "all up to date" lifecycle confirmation.
func (u *UserService) TrackJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	var req models.CreateJobRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	if req.OwnerID == "" || req.ServiceID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "owner_id and service_id are required",
		})
		return
	}

	now := time.Now().UTC()
	job := &models.Job{
		ID:         generateID(),
		OwnerID:    req.OwnerID,
		EmployeeID: req.EmployeeID,
		ServiceID:  req.ServiceID,
		Status:     models.JobStatusPending,
		Location:   req.Location,
		CreatedAt:  now,
		UpdatedAt:  now,
	}

	if err := u.store.CreateJob(job); err != nil {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": err.Error(),
		})
		return
	}

	log.Printf("[USER] Job created: id=%s owner=%s service=%s status=%s",
		job.ID, job.OwnerID, job.ServiceID, job.Status)

	// Simulate lifecycle progression: pending → active ("all up to date").
	if err := u.store.UpdateJobStatus(job.ID, models.JobStatusActive); err != nil {
		log.Printf("[USER] Failed to progress job %s: %v", job.ID, err)
	} else {
		job.Status = models.JobStatusActive
		job.UpdatedAt = time.Now().UTC()
		log.Printf("[USER] Job progressed: id=%s status=%s (all up to date)", job.ID, job.Status)
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"message":        "job tracking record created",
		"lifecycle_note": "all up to date",
		"job":            job,
	})
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func generateID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("fallback-%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

func parseFloat(s string, fallback float64) float64 {
	if s == "" {
		return fallback
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return fallback
	}
	return v
}
