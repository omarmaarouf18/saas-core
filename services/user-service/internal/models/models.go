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
type JobStatus string

const (
	JobStatusPending   JobStatus = "pending"
	JobStatusActive    JobStatus = "active"
	JobStatusCompleted JobStatus = "completed"
)

// ValidJobStatus returns true if the given status is a known value.
func ValidJobStatus(s JobStatus) bool {
	switch s {
	case JobStatusPending, JobStatusActive, JobStatusCompleted:
		return true
	}
	return false
}

// Location represents a geographic coordinate pair.
type Location struct {
	Latitude  float64 `json:"latitude"  bson:"latitude"`
	Longitude float64 `json:"longitude" bson:"longitude"`
}

// Job represents a trackable unit of work linking an owner, employee, and service.
type Job struct {
	ID         string    `json:"id"                    bson:"_id"`
	OwnerID    string    `json:"owner_id"              bson:"owner_id"`
	EmployeeID string    `json:"employee_id,omitempty" bson:"employee_id,omitempty"`
	ServiceID  string    `json:"service_id"            bson:"service_id"`
	Status     JobStatus `json:"status"                bson:"status"`
	Location   Location  `json:"location"              bson:"location"`
	CreatedAt  time.Time `json:"created_at"            bson:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"            bson:"updated_at"`
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
	Name             string  `json:"name"`
	Category         string  `json:"category"`
	TenantBasePrice  float64 `json:"tenant_base_price"`
	TenantPricePerKM float64 `json:"tenant_price_per_km"`
	Latitude         float64 `json:"latitude"`
	Longitude        float64 `json:"longitude"`
}

// CreateJobRequest is the expected JSON body for POST /users/jobs/track.
type CreateJobRequest struct {
	OwnerID    string   `json:"owner_id"`
	EmployeeID string   `json:"employee_id,omitempty"`
	ServiceID  string   `json:"service_id"`
	Location   Location `json:"location"`
}

// DepositRequest is the expected JSON body for POST /users/wallet/deposit.
type DepositRequest struct {
	TenantID string  `json:"tenant_id"`
	Amount   float64 `json:"amount"`
}

// CompleteJobRequest is the expected JSON body for POST /users/jobs/complete.
type CompleteJobRequest struct {
	JobID string `json:"job_id"`
}
