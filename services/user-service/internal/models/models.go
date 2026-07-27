// Package models defines data types for the user-service.
package models

import "time"

// ---------------------------------------------------------------------------
// GeoJSON — for MongoDB 2dsphere spatial indexing
// ---------------------------------------------------------------------------

// GeoJSONPoint represents a GeoJSON Point for spatial queries.
type GeoJSONPoint struct {
	Type        string    `json:"type"        bson:"type"`
	Coordinates []float64 `json:"coordinates" bson:"coordinates"` // [longitude, latitude]
}

// NewGeoJSONPoint creates a GeoJSON Point from lat/lon coordinates.
func NewGeoJSONPoint(lat, lon float64) GeoJSONPoint {
	return GeoJSONPoint{
		Type:        "Point",
		Coordinates: []float64{lon, lat}, // GeoJSON is [lon, lat]
	}
}

// ---------------------------------------------------------------------------
// Service — marketplace service listing
// ---------------------------------------------------------------------------

// Service represents an available service offered on the platform.
// Each service belongs to a tenant and carries tenant-specific pricing.
type Service struct {
	ID               string       `json:"id"                  bson:"_id"`
	TenantID         string       `json:"tenant_id"           bson:"tenant_id"`
	Name             string       `json:"name"                bson:"name"`
	Category         string       `json:"category"            bson:"category"`
	BasePrice        float64      `json:"base_price"          bson:"base_price"`
	TenantBasePrice  float64      `json:"tenant_base_price"   bson:"tenant_base_price"`   // tenant-specific base fee
	TenantPricePerKM float64      `json:"tenant_price_per_km" bson:"tenant_price_per_km"` // per-km surcharge
	Latitude         float64      `json:"latitude"            bson:"latitude"`
	Longitude        float64      `json:"longitude"           bson:"longitude"`
	Location         GeoJSONPoint `json:"location"            bson:"location"` // GeoJSON for spatial index
}

// ServiceWithPrice wraps a Service with a dynamically computed final price.
// FinalPrice = TenantBasePrice + (DistanceInKM × TenantPricePerKM)
type ServiceWithPrice struct {
	Service
	DistanceKM float64 `json:"distance_km"`
	FinalPrice float64 `json:"final_price"`
}

// ---------------------------------------------------------------------------
// Job — job lifecycle tracking
// ---------------------------------------------------------------------------

// JobStatus represents the current state of a job.
// JobStatusAwaitingPriceResponse represents a transport/ride job waiting for price proposal acceptance or decline.
type JobStatus string

const (
	JobStatusPending                      JobStatus = "pending"
	JobStatusAwaitingPriceResponse        JobStatus = "awaiting_price_response"
	JobStatusActive                       JobStatus = "active"
	JobStatusCompleted                    JobStatus = "completed"
	JobStatusCancelled                    JobStatus = "cancelled"
	JobStatusEscrowReconciliationRequired JobStatus = "escrow_reconciliation_required"
)

// ValidJobStatus returns true if the given status is a known value.
func ValidJobStatus(s JobStatus) bool {
	switch s {
	case JobStatusPending, JobStatusAwaitingPriceResponse, JobStatusActive, JobStatusCompleted, JobStatusCancelled, JobStatusEscrowReconciliationRequired:
		return true
	}
	return false
}

// ValidPriceProposal checks if a proposed fare falls within the allowed [0.5 × P_system, 1.5 × P_system] bound.
// Returns false if either suggested or proposed prices are non-positive (<= 0), preventing zero or negative fare manipulation.
func ValidPriceProposal(suggested, proposed float64) bool {
	if suggested <= 0 || proposed <= 0 {
		return false
	}
	minPrice := 0.5 * suggested
	maxPrice := 1.5 * suggested
	const eps = 1e-9
	return proposed >= (minPrice-eps) && proposed <= (maxPrice+eps)
}

// Location represents a geographic coordinate pair.
type Location struct {
	Latitude  float64 `json:"latitude"  bson:"latitude"`
	Longitude float64 `json:"longitude" bson:"longitude"`
}

// Job represents a trackable unit of work linking an owner, employee, and service.
type Job struct {
	ID                     string     `json:"id"                            bson:"_id"`
	OwnerID                string     `json:"owner_id"                      bson:"owner_id"`
	EmployeeID             string     `json:"employee_id,omitempty"         bson:"employee_id,omitempty"`
	UserID                 string     `json:"user_id"                       bson:"user_id"`
	ServiceID              string     `json:"service_id"                    bson:"service_id"`
	Status                 JobStatus  `json:"status"                        bson:"status"`
	Location               Location   `json:"location"                      bson:"location"`
	CurrentLocation        *Location  `json:"current_location,omitempty"   bson:"current_location,omitempty"`
	Waypoints              []Location `json:"waypoints,omitempty"          bson:"waypoints,omitempty"`
	PaymentMethod          string     `json:"payment_method"                bson:"payment_method"`
	CancellationReason     string     `json:"cancellation_reason,omitempty" bson:"cancellation_reason,omitempty"`
	LockedEscrowAmount     float64    `json:"locked_escrow_amount,omitempty" bson:"locked_escrow_amount,omitempty"`
	ReconciliationNote     string     `json:"reconciliation_note,omitempty" bson:"reconciliation_note,omitempty"`
	EscrowFailureReason    string     `json:"escrow_failure_reason,omitempty" bson:"escrow_failure_reason,omitempty"`
	SuggestedPrice         float64    `json:"suggested_price,omitempty"           bson:"suggested_price,omitempty"`
	ProposedPrice          *float64   `json:"proposed_price,omitempty"            bson:"proposed_price,omitempty"`
	ProposedBy             string     `json:"proposed_by,omitempty"               bson:"proposed_by,omitempty"`
	AgreedPrice            *float64   `json:"agreed_price,omitempty"              bson:"agreed_price,omitempty"`
	PriceProposalExpiresAt *time.Time `json:"price_proposal_expires_at,omitempty" bson:"price_proposal_expires_at,omitempty"`
	CreatedAt              time.Time  `json:"created_at"                    bson:"created_at"`
	UpdatedAt              time.Time  `json:"updated_at"                    bson:"updated_at"`
}

// OwnerJobResponse provides full tenant job visibility for business owners.
type OwnerJobResponse struct {
	ID                     string     `json:"id"`
	OwnerID                string     `json:"owner_id"`
	ServiceID              string     `json:"service_id"`
	UserID                 string     `json:"user_id"`
	EmployeeID             string     `json:"employee_id,omitempty"`
	Status                 JobStatus  `json:"status"`
	Location               Location   `json:"location"`
	PaymentMethod          string     `json:"payment_method"`
	LockedEscrowAmount     float64    `json:"locked_escrow_amount,omitempty"`
	ReconciliationNote     string     `json:"reconciliation_note,omitempty"`
	EscrowFailureReason    string     `json:"escrow_failure_reason,omitempty"`
	SuggestedPrice         float64    `json:"suggested_price,omitempty"`
	ProposedPrice          *float64   `json:"proposed_price,omitempty"`
	ProposedBy             string     `json:"proposed_by,omitempty"`
	AgreedPrice            *float64   `json:"agreed_price,omitempty"`
	PriceProposalExpiresAt *time.Time `json:"price_proposal_expires_at,omitempty"`
	CreatedAt              time.Time  `json:"created_at"`
	UpdatedAt              time.Time  `json:"updated_at"`
}

// NewOwnerJobResponse maps a Job struct to an OwnerJobResponse DTO.
func NewOwnerJobResponse(j *Job) OwnerJobResponse {
	if j == nil {
		return OwnerJobResponse{}
	}
	return OwnerJobResponse{
		ID:                     j.ID,
		OwnerID:                j.OwnerID,
		ServiceID:              j.ServiceID,
		UserID:                 j.UserID,
		EmployeeID:             j.EmployeeID,
		Status:                 j.Status,
		Location:               j.Location,
		PaymentMethod:          j.PaymentMethod,
		LockedEscrowAmount:     j.LockedEscrowAmount,
		ReconciliationNote:     j.ReconciliationNote,
		EscrowFailureReason:    j.EscrowFailureReason,
		SuggestedPrice:         j.SuggestedPrice,
		ProposedPrice:          j.ProposedPrice,
		ProposedBy:             j.ProposedBy,
		AgreedPrice:            j.AgreedPrice,
		PriceProposalExpiresAt: j.PriceProposalExpiresAt,
		CreatedAt:              j.CreatedAt,
		UpdatedAt:              j.UpdatedAt,
	}
}

// CustomerJobResponse provides job booking history for customers, excluding internal tenant & financial fields.
type CustomerJobResponse struct {
	ID                     string     `json:"id"`
	ServiceID              string     `json:"service_id"`
	EmployeeID             string     `json:"employee_id,omitempty"`
	Status                 JobStatus  `json:"status"`
	Location               Location   `json:"location"`
	PaymentMethod          string     `json:"payment_method"`
	SuggestedPrice         float64    `json:"suggested_price,omitempty"`
	ProposedPrice          *float64   `json:"proposed_price,omitempty"`
	ProposedBy             string     `json:"proposed_by,omitempty"`
	AgreedPrice            *float64   `json:"agreed_price,omitempty"`
	PriceProposalExpiresAt *time.Time `json:"price_proposal_expires_at,omitempty"`
	CreatedAt              time.Time  `json:"created_at"`
	UpdatedAt              time.Time  `json:"updated_at"`
}

// NewCustomerJobResponse maps a Job struct to a CustomerJobResponse DTO.
func NewCustomerJobResponse(j *Job) CustomerJobResponse {
	if j == nil {
		return CustomerJobResponse{}
	}
	return CustomerJobResponse{
		ID:                     j.ID,
		ServiceID:              j.ServiceID,
		EmployeeID:             j.EmployeeID,
		Status:                 j.Status,
		Location:               j.Location,
		PaymentMethod:          j.PaymentMethod,
		SuggestedPrice:         j.SuggestedPrice,
		ProposedPrice:          j.ProposedPrice,
		ProposedBy:             j.ProposedBy,
		AgreedPrice:            j.AgreedPrice,
		PriceProposalExpiresAt: j.PriceProposalExpiresAt,
		CreatedAt:              j.CreatedAt,
		UpdatedAt:              j.UpdatedAt,
	}
}

// ---------------------------------------------------------------------------
// Financial — Wallet, Ledger, Platform Config
// ---------------------------------------------------------------------------

// Wallet tracks the financial balance of a tenant (owner).
type Wallet struct {
	ID                  string    `json:"id"                   bson:"_id"`
	TenantID            string    `json:"tenant_id"            bson:"tenant_id"`
	TotalBalance        float64   `json:"total_balance"        bson:"total_balance"`
	EscrowBalance       float64   `json:"escrow_balance"       bson:"escrow_balance"`       // locked/pending funds
	WithdrawableBalance float64   `json:"withdrawable_balance" bson:"withdrawable_balance"` // available funds
	UpdatedAt           time.Time `json:"updated_at"           bson:"updated_at"`
}

// TransactionType defines the kind of ledger entry.
type TransactionType string

const (
	TxEscrowLock    TransactionType = "escrow_lock"
	TxEscrowRelease TransactionType = "escrow_release"
	TxPlatformFee   TransactionType = "platform_fee"
	TxPayout        TransactionType = "payout"
	TxDeposit       TransactionType = "deposit"
)

// TransactionLedger is an immutable audit record for every balance modification.
type TransactionLedger struct {
	ID            string          `json:"id"             bson:"_id"`
	TenantID      string          `json:"tenant_id"      bson:"tenant_id"`
	JobID         string          `json:"job_id"         bson:"job_id"`
	Type          TransactionType `json:"type"           bson:"type"`
	Amount        float64         `json:"amount"         bson:"amount"`
	BalanceBefore float64         `json:"balance_before" bson:"balance_before"`
	BalanceAfter  float64         `json:"balance_after"  bson:"balance_after"`
	Description   string          `json:"description"    bson:"description"`
	Timestamp     time.Time       `json:"timestamp"      bson:"timestamp"`
}

// PlatformConfig stores global financial parameters.
type PlatformConfig struct {
	ID                    string  `json:"id"                      bson:"_id"`
	PlatformFeePercentage float64 `json:"platform_fee_percentage" bson:"platform_fee_percentage"`
	PlatformWalletID      string  `json:"platform_wallet_id"      bson:"platform_wallet_id"`
}

// ---------------------------------------------------------------------------
// Request / Response types
// ---------------------------------------------------------------------------

// CreateServiceRequest is the expected JSON body for POST /users/services.
type CreateServiceRequest struct {
	OwnerID          string  `json:"owner_id"`
	OwnerToken       string  `json:"owner_token,omitempty"`
	Name             string  `json:"name"`
	Category         string  `json:"category"`
	TenantBasePrice  float64 `json:"tenant_base_price"`
	TenantPricePerKM float64 `json:"tenant_price_per_km"`
	Latitude         float64 `json:"latitude"`
	Longitude        float64 `json:"longitude"`
}

// CreateJobRequest is the expected JSON body for POST /users/jobs/track.
type CreateJobRequest struct {
	OwnerID        string   `json:"owner_id"`
	OwnerToken     string   `json:"owner_token,omitempty"`
	EmployeeID     string   `json:"employee_id,omitempty"`
	EmployeeToken  string   `json:"employee_token,omitempty"`
	ServiceID      string   `json:"service_id"`
	Location       Location `json:"location"`
	PaymentMethod  string   `json:"payment_method"`
	UserID         string   `json:"user_id"`
	UserToken      string   `json:"user_token,omitempty"`
	IdempotencyKey string   `json:"idempotency_key,omitempty"`
	ProposedPrice  *float64 `json:"proposed_price,omitempty"`
}

// DepositRequest is the expected JSON body for POST /users/wallet/deposit.
type DepositRequest struct {
	TenantID    string  `json:"tenant_id"`
	TenantToken string  `json:"tenant_token,omitempty"`
	Amount      float64 `json:"amount"`
}

// CompleteJobRequest is the expected JSON body for POST /users/jobs/complete.
type CompleteJobRequest struct {
	JobID          string `json:"job_id"`
	CashCollected  bool   `json:"cash_collected"`
	RequesterID    string `json:"requester_id"`
	RequesterToken string `json:"requester_token,omitempty"`
}

type PlanTier string

const (
	PlanFree           PlanTier = "free"
	PlanPaid           PlanTier = "paid"
	PlanPendingPayment PlanTier = "pending_payment"
)

type Subscription struct {
	ID        string    `json:"id"         bson:"_id"`
	TenantID  string    `json:"tenant_id"  bson:"tenant_id"`
	Tier      PlanTier  `json:"tier"       bson:"tier"`
	StartedAt time.Time `json:"started_at" bson:"started_at"`
	ExpiresAt time.Time `json:"expires_at,omitempty" bson:"expires_at,omitempty"` // zero = no expiry (free tier)
}

type Rating struct {
	ID        string    `json:"id"         bson:"_id"`
	JobID     string    `json:"job_id"     bson:"job_id"`
	RatedBy   string    `json:"rated_by"   bson:"rated_by"`   // user ID submitting
	RatedUser string    `json:"rated_user" bson:"rated_user"` // user ID being rated
	Stars     int       `json:"stars"      bson:"stars"`      // 1-5
	Comment   string    `json:"comment,omitempty" bson:"comment,omitempty"`
	CreatedAt time.Time `json:"created_at" bson:"created_at"`
}
