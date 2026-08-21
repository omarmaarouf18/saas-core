// Package handlers implements HTTP handlers for the user-service.
package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

var ErrServiceUnavailable = errors.New("service_unavailable")

// ErrUpgradeRequired is returned when a tenant's subscription tier is insufficient for a gated feature.
var ErrUpgradeRequired = errors.New("upgrade_required")

// MinLocationUpdateInterval defines the minimum wait time between consecutive location updates per job.
const MinLocationUpdateInterval = 3 * time.Second

// MaxReasonableSpeedKmh defines the maximum plausible speed for location updates in km/h.
const MaxReasonableSpeedKmh = 150.0

const checkLocationThrottleScript = `
local inflightKey = KEYS[1]
local lastupdateKey = KEYS[2]

local minIntervalMs = tonumber(ARGV[1])
local inflightTTLSec = tonumber(ARGV[2])
local nowMs = tonumber(ARGV[3])

-- 1. Check in-flight lock
if redis.call('EXISTS', inflightKey) == 1 then
    return {1, 0}
end

-- 2. Check last update timestamp
local lastUpdateMsStr = redis.call('GET', lastupdateKey)
local lastUpdateMs = 0
if lastUpdateMsStr then
    lastUpdateMs = tonumber(lastUpdateMsStr) or 0
    if lastUpdateMs > 0 and (nowMs - lastUpdateMs) < minIntervalMs then
        return {2, lastUpdateMs}
    end
end

-- 3. Set in-flight key atomically
redis.call('SET', inflightKey, '1', 'EX', inflightTTLSec)

return {0, lastUpdateMs}
`

// UserService holds dependencies for the user-service handlers.
type UserService struct {
	store                     *store.MongoDB
	authServiceURL            string
	chatServiceURL            string
	notificationServiceURL    string
	limiter                   *handlerutil.RateLimiter
	ownerJobsLimiter          *handlerutil.RateLimiter
	customerJobsLimiter       *handlerutil.RateLimiter
	ledgerLimiter             *handlerutil.RateLimiter
	ledgerIPLimiter           *handlerutil.RateLimiter
	ratingsLimiter            *handlerutil.RateLimiter
	reconciliationLimiter     *handlerutil.RateLimiter
	completeJobLimiter        *handlerutil.RateLimiter
	resolveReconLimiter       *handlerutil.RateLimiter
	payoutLimiter             *handlerutil.RateLimiter
	internalServiceToken      string
	locationThrottleMu        sync.Mutex
	locationLastUpdate        map[string]time.Time
	locationInFlight          map[string]bool
	authClient                *resilience.ResilienceClient
	chatClient                *resilience.ResilienceClient
	notificationClient        *resilience.ResilienceClient
	httpClient                *http.Client
	appEnv                    string
	allowTestPaymentBypass    bool
	electronicPaymentsEnabled bool
	rdb                       *redis.Client
	// Test hook to block UpdateJobLocation database write for deterministic testing
	updateJobLocationBeforeWriteHook func(ctx context.Context)
	// Test hook to force RollbackEscrow to fail for deterministic testing
	rollbackEscrowHook func(ctx context.Context, tenantID string, amount float64) error
	// Test hook to simulate concurrent job status change before UpdateJobAgreedPrice
	updateJobAgreedPriceBeforeWriteHook func(ctx context.Context)
	// Test hook to simulate generic requireTier error for deterministic testing
	requireTierHook func(ctx context.Context, tenantID string, min models.PlanTier) error
}

func (u *UserService) clearLocationThrottleState(jobID string) {
	u.locationThrottleMu.Lock()
	delete(u.locationLastUpdate, jobID)
	delete(u.locationInFlight, jobID)
	u.locationThrottleMu.Unlock()

	if u.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = u.rdb.Del(ctx, fmt.Sprintf("loc:inflight:%s", jobID), fmt.Sprintf("loc:lastupdate:%s", jobID)).Err()
	}
}

func (u *UserService) tryReserveLocationThrottleInMemory(jobID string, now time.Time) (code int, errMessage string) {
	u.locationThrottleMu.Lock()
	defer u.locationThrottleMu.Unlock()

	if u.locationInFlight[jobID] {
		return 1, "Location update is already in progress for this job."
	}

	if lastUpdate, ex := u.locationLastUpdate[jobID]; ex {
		elapsed := now.Sub(lastUpdate)
		if elapsed < MinLocationUpdateInterval {
			return 2, fmt.Sprintf("Too many location updates. Minimum interval is %.0f seconds.", MinLocationUpdateInterval.Seconds())
		}
	}

	u.locationInFlight[jobID] = true
	return 0, ""
}

func (u *UserService) setTestLocationLastUpdate(jobID string, t time.Time) {
	u.locationThrottleMu.Lock()
	u.locationLastUpdate[jobID] = t
	u.locationThrottleMu.Unlock()

	if u.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		nowMs := t.UnixNano() / int64(time.Millisecond)
		_ = u.rdb.Set(ctx, fmt.Sprintf("loc:lastupdate:%s", jobID), fmt.Sprintf("%d", nowMs), 300*time.Second).Err()
	}
}

// NewUserService creates a new UserService handler group.
func NewUserService(s *store.MongoDB, cfg *config.Config, rdb *redis.Client) *UserService {
	handlerutil.InitCloudWatch(cfg.CloudWatchLogGroup)

	chatServiceURL := cfg.ChatServiceURL
	if chatServiceURL == "" {
		chatServiceURL = "http://localhost:3001"
	}

	notificationServiceURL := cfg.NotificationServiceURL
	if notificationServiceURL == "" {
		notificationServiceURL = "http://localhost:3004"
	}

	var client *http.Client
	if cfg.TLSCertPath != "" && cfg.TLSKeyPath != "" && cfg.TLSCAPath != "" {
		var err error
		client, err = tlsutil.NewClient(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
		if err != nil {
			log.Fatalf("[USER] Failed to initialize TLS http client: %v", err)
		}
	} else {
		client = http.DefaultClient
	}

	rl := ratelimit.NewRateLimiter(rdb, 5, 1*time.Minute, "user")
	rlOwnerJobs := ratelimit.NewRateLimiter(rdb, 60, 1*time.Minute, "user:owner_jobs")
	rlCustomerJobs := ratelimit.NewRateLimiter(rdb, 60, 1*time.Minute, "user:customer_jobs")
	rlLedger := ratelimit.NewRateLimiter(rdb, 60, 1*time.Minute, "user:ledger")
	rlLedgerIP := ratelimit.NewRateLimiter(rdb, 60, 1*time.Minute, "user:ledger_ip")
	rlRatings := ratelimit.NewRateLimiter(rdb, 30, 1*time.Minute, "user:ratings")
	rlReconciliation := ratelimit.NewRateLimiter(rdb, 30, 1*time.Minute, "user:reconciliation")
	rlCompleteJob := ratelimit.NewRateLimiter(rdb, 30, 1*time.Minute, "user:complete_job")
	rlResolveRecon := ratelimit.NewRateLimiter(rdb, 30, 1*time.Minute, "user:reconciliation_resolve")
	rlPayout := ratelimit.NewRateLimiter(rdb, 30, 1*time.Minute, "user:payout")

	authClient := resilience.NewClient(client, "auth-service", 2, 5*time.Second)
	chatClient := resilience.NewClient(client, "chat-service", 2, 5*time.Second)
	notificationClient := resilience.NewClient(client, "notification-service", 2, 5*time.Second)

	return &UserService{
		store:                     s,
		authServiceURL:            cfg.AuthServiceURL,
		chatServiceURL:            chatServiceURL,
		notificationServiceURL:    notificationServiceURL,
		limiter:                   handlerutil.NewRateLimiter(rl),
		ownerJobsLimiter:          handlerutil.NewRateLimiter(rlOwnerJobs),
		customerJobsLimiter:       handlerutil.NewRateLimiter(rlCustomerJobs),
		ledgerLimiter:             handlerutil.NewRateLimiter(rlLedger),
		ledgerIPLimiter:           handlerutil.NewRateLimiter(rlLedgerIP),
		ratingsLimiter:            handlerutil.NewRateLimiter(rlRatings),
		reconciliationLimiter:     handlerutil.NewRateLimiter(rlReconciliation),
		completeJobLimiter:        handlerutil.NewRateLimiter(rlCompleteJob),
		resolveReconLimiter:       handlerutil.NewRateLimiter(rlResolveRecon),
		payoutLimiter:             handlerutil.NewRateLimiter(rlPayout),
		internalServiceToken:      cfg.InternalServiceToken,
		locationLastUpdate:        make(map[string]time.Time),
		locationInFlight:          make(map[string]bool),
		rdb:                       rdb,
		authClient:                authClient,
		chatClient:                chatClient,
		notificationClient:        notificationClient,
		httpClient:                client,
		appEnv:                    cfg.AppEnv,
		allowTestPaymentBypass:    cfg.AllowTestPaymentBypass,
		electronicPaymentsEnabled: cfg.ElectronicPaymentsEnabled,
	}
}

// RegisterRoutes mounts all user-service endpoints on the given ServeMux.
func (u *UserService) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/users/services", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			u.ListServices(w, r)
		case http.MethodPost:
			u.CreateService(w, r)
		case http.MethodPut, http.MethodPatch:
			u.UpdateService(w, r)
		default:
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	})
	mux.HandleFunc("/users/services/update", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodPost, http.MethodPut, http.MethodPatch:
			u.UpdateService(w, r)
		default:
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	})
	mux.HandleFunc("/users/jobs/track", u.TrackJob)
	mux.HandleFunc("/users/jobs/get", u.GetJob)
	mux.HandleFunc("/users/jobs/owner", u.GetOwnerJobs)
	mux.HandleFunc("/users/jobs/mine", u.GetCustomerJobs)
	mux.HandleFunc("/users/jobs/complete", u.CompleteJob)
	mux.HandleFunc("/users/jobs/cancel", u.CancelJob)
	mux.HandleFunc("/users/jobs/propose-price", u.ProposePrice)
	mux.HandleFunc("/users/jobs/respond-price", u.RespondPrice)
	mux.HandleFunc("/users/wallet", u.GetWallet)
	mux.HandleFunc("/users/wallet/deposit", u.WalletDeposit)
	mux.HandleFunc("/users/wallet/payout/request", u.RequestPayout)
	mux.HandleFunc("/users/wallet/payout/requests", u.GetPayoutRequests)
	mux.HandleFunc("/users/ledger", u.GetLedger)
	mux.HandleFunc("/users/platform/config", u.GetPlatformConfig)
	mux.HandleFunc("/users/subscription", u.Subscription)
	mux.HandleFunc("/users/jobs/rate", u.RateJob)
	mux.HandleFunc("/users/ratings", u.GetRatings)
	mux.HandleFunc("/users/jobs/location/update", u.UpdateJobLocation)
	mux.HandleFunc("/users/jobs/reconciliation-queue", u.GetReconciliationQueue)
	mux.HandleFunc("/users/jobs/reconciliation-resolve", u.ResolveReconciliation)
}

// ---------------------------------------------------------------------------
// Shared Package-Level Helpers
// ---------------------------------------------------------------------------

func resolveClaims(tokenStr string) (*jwtutil.Claims, error) {
	claims, err := jwtutil.ValidateToken(tokenStr)
	if err != nil {
		return nil, fmt.Errorf("invalid or missing token: %w", err)
	}
	return claims, nil
}

func resolveTokenWithRole(tokenStr string, allowedRoles ...string) (string, error) {
	claims, err := resolveClaims(tokenStr)
	if err != nil {
		return "", err
	}
	if len(allowedRoles) > 0 {
		matched := false
		for _, role := range allowedRoles {
			if claims.Role == role {
				matched = true
				break
			}
		}
		if !matched {
			return "", fmt.Errorf("role mismatch: claim role %q not in allowed roles %v", claims.Role, allowedRoles)
		}
	}
	return claims.UserID, nil
}

// idempotencyPendingValue marks a reserved-but-incomplete idempotency slot.
const idempotencyPendingValue = "__pending__"

// saveIdempotencyKey records the completed job ID for a per-user idempotency
// key. Idempotency bookkeeping is deliberately NOT tied to the inbound request
// context: a client disconnect between job creation and key-set previously
// cancelled the write, dropping the key and causing client retries to
// double-book funded jobs.
func (u *UserService) saveIdempotencyKey(userID, key, jobID string) {
	if key != "" && u.rdb != nil {
		redisKey := "idempotency:job:" + userID + ":" + key
		if err := u.rdb.Set(context.Background(), redisKey, jobID, 24*time.Hour).Err(); err != nil {
			// #nosec G706 //nolint:gosec -- key comes from request header/body, used for failure diagnosis
			log.Printf("[ERROR] failed to store idempotency key %s in Redis: %v", key, err)
		}
	}
}

// reserveIdempotencyKey atomically claims the per-user idempotency slot via
// SET NX, closing the concurrent-duplicate race where two requests could both
// miss the replay check and both create funded jobs. It returns:
//   - replayJobID != "" : a completed request already exists under this key —
//     serve its job as an idempotent replay.
//   - conflict == true  : another identical request holds a pending
//     reservation — reject with 409 instead of double-booking.
//
// Redis unavailability degrades to non-idempotent operation (logged), matching
// the pre-existing availability behaviour of the replay check.
func (u *UserService) reserveIdempotencyKey(userID, key string) (replayJobID string, conflict bool) {
	if key == "" || u.rdb == nil {
		return "", false
	}
	redisKey := "idempotency:job:" + userID + ":" + key

	existing, err := u.rdb.Get(context.Background(), redisKey).Result()
	if err == nil && existing != "" && existing != idempotencyPendingValue {
		return existing, false
	}

	reserved, err := u.rdb.SetNX(context.Background(), redisKey, idempotencyPendingValue, 24*time.Hour).Result()
	if err != nil {
		log.Printf("[WARN] idempotency reservation unavailable, proceeding without dedupe: %v", err)
		return "", false
	}
	if !reserved {
		val, err := u.rdb.Get(context.Background(), redisKey).Result()
		if err == nil && val != "" && val != idempotencyPendingValue {
			return val, false // lost the race but the winner already finished
		}
		return "", true // genuine concurrent in-flight duplicate
	}
	return "", false
}

// releaseIdempotencyReservation drops a pending reservation after a failure
// path that did NOT persist a job, so legitimate client retries are not
// blocked by a stale pending marker. Safe to call when no reservation exists.
func (u *UserService) releaseIdempotencyReservation(userID, key string) {
	if key == "" || u.rdb == nil {
		return
	}
	_ = u.rdb.Del(context.Background(), "idempotency:job:"+userID+":"+key).Err()
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	handlerutil.WriteJSON(w, status, data)
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

func (u *UserService) checkKYC(ownerID string) (string, error) {
	url := fmt.Sprintf("%s/auth/user?id=%s", u.authServiceURL, ownerID)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("X-Internal-Token", u.internalServiceToken)
	resp, err := u.authClient.Do(req)
	if err != nil {
		return "", ErrServiceUnavailable
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return "", fmt.Errorf("owner not found")
	}
	if resp.StatusCode != http.StatusOK {
		return "", ErrServiceUnavailable
	}

	var user struct {
		Role      string `json:"role"`
		KYCStatus string `json:"kyc_status"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return "", err
	}

	if user.Role != "owner" {
		return "", fmt.Errorf("specified user is not an owner")
	}

	return user.KYCStatus, nil
}

func (u *UserService) verifyEmployeeAssignment(employeeID, ownerID string) (bool, error) {
	url := fmt.Sprintf("%s/auth/user?id=%s", u.authServiceURL, employeeID)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("X-Internal-Token", u.internalServiceToken)
	resp, err := u.authClient.Do(req)
	if err != nil {
		return false, ErrServiceUnavailable
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return false, fmt.Errorf("employee not found")
	}
	if resp.StatusCode != http.StatusOK {
		return false, ErrServiceUnavailable
	}

	var user struct {
		Role     string `json:"role"`
		TenantID string `json:"tenant_id"`
		IsActive bool   `json:"is_active"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return false, err
	}

	if user.Role != "employee" || user.TenantID != ownerID || !user.IsActive {
		return false, nil
	}

	return true, nil
}

// requireTier enforces that a tenant has at least the minimum subscription tier.
func (u *UserService) requireTier(ctx context.Context, tenantID string, min models.PlanTier) error {
	if u.requireTierHook != nil {
		if err := u.requireTierHook(ctx, tenantID, min); err != nil {
			return err
		}
	}
	sub := u.store.GetSubscription(ctx, tenantID)
	var currentTier models.PlanTier = models.PlanFree
	if sub != nil {
		currentTier = sub.Tier
	}

	if min == models.PlanPaid {
		if currentTier != models.PlanPaid {
			return ErrUpgradeRequired
		}
	}
	return nil
}
