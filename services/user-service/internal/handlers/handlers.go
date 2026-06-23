// Package handlers implements HTTP handlers for the user-service.
package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

// UserService holds dependencies for the user-service handlers.
type UserService struct {
	store *store.MongoDB
}

// NewUserService creates a new handler group.
func NewUserService(s *store.MongoDB) *UserService {
	return &UserService{store: s}
}

// RegisterRoutes mounts all user-service endpoints on the given ServeMux.
func (u *UserService) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/users/services", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			u.ListServices(w, r)
		case http.MethodPost:
			u.CreateService(w, r)
		default:
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	})
	mux.HandleFunc("/users/jobs/track", u.TrackJob)
	mux.HandleFunc("/users/jobs/complete", u.CompleteJob)
	mux.HandleFunc("/users/wallet", u.GetWallet)
	mux.HandleFunc("/users/wallet/deposit", u.WalletDeposit)
	mux.HandleFunc("/users/ledger", u.GetLedger)
	mux.HandleFunc("/users/platform/config", u.GetPlatformConfig)
}

// ---------------------------------------------------------------------------
// GET /users/services
// ---------------------------------------------------------------------------

func (u *UserService) ListServices(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	sortBy := q.Get("sort_by")
	nearBy := q.Get("near_by") == "true"
	refLat := parseFloat(q.Get("lat"), 30.0444)
	refLon := parseFloat(q.Get("lon"), 31.2357)
	radius := parseFloat(q.Get("radius"), 50)

	ctx := r.Context()
	services := u.store.ListServices(ctx, sortBy, nearBy, refLat, refLon, radius)
	log.Printf("[USER] ListServices: sort_by=%s near_by=%v results=%d", sortBy, nearBy, len(services))

	writeJSON(w, http.StatusOK, map[string]any{
		"count": len(services), "sort_by": sortBy, "near_by": nearBy, "services": services,
	})
}

// ---------------------------------------------------------------------------
// POST /users/services
// ---------------------------------------------------------------------------

func (u *UserService) CreateService(w http.ResponseWriter, r *http.Request) {
	var req models.CreateServiceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.OwnerID == "" || req.Name == "" || req.Category == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "owner_id, name, and category are required"})
		return
	}
	if req.Category != "shipping" && req.Category != "delivery" && req.Category != "transport" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid category, must be: shipping, delivery, transport"})
		return
	}

	svc := &models.Service{
		ID: generateID(), TenantID: req.OwnerID, Name: req.Name, Category: req.Category,
		BasePrice: req.TenantBasePrice, TenantBasePrice: req.TenantBasePrice,
		TenantPricePerKM: req.TenantPricePerKM, Latitude: req.Latitude, Longitude: req.Longitude,
	}

	u.store.CreateService(r.Context(), svc)
	log.Printf("[USER] Service created: id=%s name=%s", svc.ID, svc.Name)
	writeJSON(w, http.StatusCreated, map[string]any{"message": "service created", "service": svc})
}

// ---------------------------------------------------------------------------
// POST /users/jobs/track — with escrow locking
// ---------------------------------------------------------------------------

func (u *UserService) TrackJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}
	var req models.CreateJobRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.OwnerID == "" || req.ServiceID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "owner_id and service_id are required"})
		return
	}

	ctx := r.Context()

	// Look up service to calculate escrow amount.
	svc := u.store.GetServiceByID(ctx, req.ServiceID)
	if svc == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service not found"})
		return
	}

	// Calculate ride cost: base_price + (distance × price_per_km).
	dist := haversineKm(req.Location.Latitude, req.Location.Longitude, svc.Latitude, svc.Longitude)
	escrowAmount := math.Round((svc.TenantBasePrice+(dist*svc.TenantPricePerKM))*100) / 100

	now := time.Now().UTC()
	job := &models.Job{
		ID: generateID(), OwnerID: req.OwnerID, EmployeeID: req.EmployeeID,
		ServiceID: req.ServiceID, Status: models.JobStatusPending,
		Location: req.Location, CreatedAt: now, UpdatedAt: now,
	}

	if err := u.store.CreateJob(ctx, job); err != nil {
		writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
		return
	}

	// Lock escrow for this job.
	if err := u.store.LockEscrow(ctx, req.OwnerID, job.ID, escrowAmount); err != nil {
		log.Printf("[USER] Escrow lock failed for job %s: %v", job.ID, err)
		// Job created but unfunded — still report it.
		writeJSON(w, http.StatusCreated, map[string]any{
			"message": "job created but escrow lock failed — deposit funds first",
			"warning": err.Error(), "job": job, "escrow_amount": escrowAmount,
		})
		return
	}

	log.Printf("[USER] Job %s created with escrow %.2f locked", job.ID, escrowAmount)

	// Progress to active.
	u.store.UpdateJobStatus(ctx, job.ID, models.JobStatusActive)
	job.Status = models.JobStatusActive
	job.UpdatedAt = time.Now().UTC()

	writeJSON(w, http.StatusCreated, map[string]any{
		"message": "job tracking record created", "lifecycle_note": "escrow locked, all up to date",
		"job": job, "escrow_locked": escrowAmount,
	})
}

// ---------------------------------------------------------------------------
// POST /users/jobs/complete — escrow release with profit split
// ---------------------------------------------------------------------------

func (u *UserService) CompleteJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}
	var req models.CompleteJobRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.JobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id is required"})
		return
	}

	ctx := r.Context()
	job := u.store.GetJob(ctx, req.JobID)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}
	if job.Status == models.JobStatusCompleted {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "job already completed"})
		return
	}

	// Recalculate the amount to release.
	svc := u.store.GetServiceByID(ctx, job.ServiceID)
	if svc == nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "service not found for job"})
		return
	}
	dist := haversineKm(job.Location.Latitude, job.Location.Longitude, svc.Latitude, svc.Longitude)
	amount := math.Round((svc.TenantBasePrice+(dist*svc.TenantPricePerKM))*100) / 100

	// Release escrow with profit splitting.
	if err := u.store.ReleaseEscrowWithSplit(ctx, job.OwnerID, job.ID, amount); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "escrow release failed: " + err.Error()})
		return
	}

	u.store.UpdateJobStatus(ctx, job.ID, models.JobStatusCompleted)

	cfg := u.store.GetPlatformConfig(ctx)
	feePercent := 15.0
	if cfg != nil {
		feePercent = cfg.PlatformFeePercentage
	}
	fee := math.Round(amount*feePercent) / 100
	net := amount - fee

	log.Printf("[USER] Job %s completed: total=%.2f fee=%.2f net=%.2f", job.ID, amount, fee, net)
	writeJSON(w, http.StatusOK, map[string]any{
		"message": "job completed — profit split executed",
		"job_id": job.ID, "total_amount": amount,
		"platform_fee": fee, "platform_fee_pct": feePercent,
		"net_to_tenant": net,
	})
}

// ---------------------------------------------------------------------------
// GET /users/wallet?tenant_id=xxx
// ---------------------------------------------------------------------------

func (u *UserService) GetWallet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id required"})
		return
	}
	wallet, err := u.store.GetOrCreateWallet(r.Context(), tenantID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, wallet)
}

// ---------------------------------------------------------------------------
// POST /users/wallet/deposit
// ---------------------------------------------------------------------------

func (u *UserService) WalletDeposit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}
	var req models.DepositRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.TenantID == "" || req.Amount <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id and positive amount required"})
		return
	}
	if err := u.store.Deposit(r.Context(), req.TenantID, req.Amount); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	wallet := u.store.GetWallet(r.Context(), req.TenantID)
	writeJSON(w, http.StatusOK, map[string]any{"message": "deposit successful", "wallet": wallet})
}

// ---------------------------------------------------------------------------
// GET /users/ledger?tenant_id=xxx
// ---------------------------------------------------------------------------

func (u *UserService) GetLedger(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id required"})
		return
	}
	entries := u.store.GetLedger(r.Context(), tenantID)
	writeJSON(w, http.StatusOK, map[string]any{"count": len(entries), "entries": entries})
}

// GET /users/platform/config
func (u *UserService) GetPlatformConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}
	cfg := u.store.GetPlatformConfig(r.Context())
	if cfg == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "no platform config"})
		return
	}
	writeJSON(w, http.StatusOK, cfg)
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

func haversineKm(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371.0
	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	return R * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
