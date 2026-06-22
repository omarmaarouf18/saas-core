// Package models defines data types for the user-service.
package models

import "time"

// ---------------------------------------------------------------------------
// Service — marketplace service listing
// ---------------------------------------------------------------------------

// Service represents an available service offered on the platform.
// Each service belongs to a tenant and carries tenant-specific pricing.
type Service struct {
	ID               string  `json:"id"`
	Name             string  `json:"name"`
	Category         string  `json:"category"`
	BasePrice        float64 `json:"base_price"`
	TenantBasePrice  float64 `json:"tenant_base_price"`   // tenant-specific base fee
	TenantPricePerKM float64 `json:"tenant_price_per_km"` // per-km surcharge
	Latitude         float64 `json:"latitude"`
	Longitude        float64 `json:"longitude"`
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
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

// Job represents a trackable unit of work linking an owner, employee, and service.
type Job struct {
	ID         string    `json:"id"`
	OwnerID    string    `json:"owner_id"`
	EmployeeID string    `json:"employee_id,omitempty"`
	ServiceID  string    `json:"service_id"`
	Status     JobStatus `json:"status"`
	Location   Location  `json:"location"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
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
