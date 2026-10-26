// Package models defines data types for the user-service.
package models

import (
	"math"
	"regexp"
	"strings"
	"time"
	"unicode"
)

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
	ID               string       `json:"id"                            bson:"_id"`
	TenantID         string       `json:"tenant_id"                     bson:"tenant_id"`
	Name             string       `json:"name"                          bson:"name"`
	Category         string       `json:"category"                      bson:"category"`
	BasePrice        float64      `json:"base_price"                    bson:"base_price"`
	TenantBasePrice  float64      `json:"tenant_base_price"             bson:"tenant_base_price"`   // tenant-specific base fee
	TenantPricePerKM float64      `json:"tenant_price_per_km"           bson:"tenant_price_per_km"` // per-km surcharge
	Latitude         float64      `json:"latitude"                      bson:"latitude"`
	Longitude        float64      `json:"longitude"                     bson:"longitude"`
	Location         GeoJSONPoint `json:"location"                      bson:"location"` // GeoJSON for spatial index
	PhotoURL         string       `json:"photo_url,omitempty"           bson:"photo_url,omitempty"`
	Address          string       `json:"address,omitempty"             bson:"address,omitempty"`
	WorkingHours     string       `json:"working_hours,omitempty"       bson:"working_hours,omitempty"`
	CoverageRadiusKM float64      `json:"coverage_radius_km,omitempty"   bson:"coverage_radius_km,omitempty"`
	// Structured weekly schedule (ADR-0025). Additive: the legacy WorkingHours
	// free-text string is untouched and remains a display fallback. All five
	// fields empty means "unknown schedule", which always evaluates as open.
	ScheduleMode   string        `json:"schedule_mode,omitempty"    bson:"schedule_mode,omitempty"` // "same_daily" | "per_day"
	OpenTime       string        `json:"open_time,omitempty"        bson:"open_time,omitempty"`     // "HH:mm" 24h, same_daily
	CloseTime      string        `json:"close_time,omitempty"       bson:"close_time,omitempty"`    // "HH:mm" 24h, same_daily
	PerDaySchedule []DaySchedule `json:"per_day_schedule,omitempty" bson:"per_day_schedule,omitempty"`
	Timezone       string        `json:"timezone,omitempty"         bson:"timezone,omitempty"` // IANA, default "Africa/Cairo"
}

// Schedule mode literals for Service.ScheduleMode (ADR-0025).
const (
	ScheduleModeSameDaily = "same_daily"
	ScheduleModePerDay    = "per_day"
)

// DefaultServiceTimezone is used when a service has no timezone set or the
// stored value fails to load (ADR-0025: never fail closed on tz data).
const DefaultServiceTimezone = "Africa/Cairo"

// Canonical weekday keys for PerDaySchedule (lowercase, Monday-first here
// only for documentation; evaluation accepts any order but requires all 7).
var scheduleWeekdays = []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}

// DaySchedule is one weekday row of a per_day schedule (ADR-0025).
type DaySchedule struct {
	Day       string `json:"day"        bson:"day"` // "mon".."sun" (case-insensitive)
	OpenTime  string `json:"open_time"  bson:"open_time"`
	CloseTime string `json:"close_time" bson:"close_time"`
	IsOff     bool   `json:"is_off"     bson:"is_off"`
}

// ServiceWithPrice wraps a Service with a dynamically computed final price.
// FinalPrice = TenantBasePrice + (DistanceInKM × TenantPricePerKM)
type ServiceWithPrice struct {
	Service
	DistanceKM float64 `json:"distance_km"`
	FinalPrice float64 `json:"final_price"`
	// Computed at request time, never persisted (ADR-0025). IsOpenNow is
	// always present; ReopensAt is an explicit JSON null when the next
	// opening is unknown or not computable.
	IsOpenNow bool       `json:"is_open_now"`
	ReopensAt *time.Time `json:"reopens_at"`
}

// ---------------------------------------------------------------------------
// Job — job lifecycle tracking
// ---------------------------------------------------------------------------

// JobStatus represents the current state of a job.
// JobStatusAwaitingPriceResponse represents a transport/ride job waiting for price proposal acceptance or decline.
type JobStatus string

const (
	JobStatusPending                      JobStatus = "pending"
	JobStatusPendingDispatch              JobStatus = "pending_dispatch"
	JobStatusUnavailable                  JobStatus = "unavailable"
	JobStatusAwaitingPriceResponse        JobStatus = "awaiting_price_response"
	JobStatusActive                       JobStatus = "active"
	JobStatusCompleted                    JobStatus = "completed"
	JobStatusCancelled                    JobStatus = "cancelled"
	JobStatusEscrowReconciliationRequired JobStatus = "escrow_reconciliation_required"
)

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

// Location represents a geographic coordinate pair, optionally annotated
// with a free-text landmark note (Option C, no ADR: passive display string,
// no validation beyond length, no state/auth/money semantics — same class
// as CreateServiceRequest.Address and the Destination field itself, both
// of which shipped without ADRs).
type Location struct {
	Latitude  float64 `json:"latitude"  bson:"latitude"`
	Longitude float64 `json:"longitude" bson:"longitude"`
	// Address is structured free text (street, area, building) typed or
	// selected by the customer at booking time (ADR-0028 §2.2). Snapshotted
	// into the job; later profile edits never cascade back into it. No paid
	// geocoding: it is stored exactly as provided, trimmed and sanitized.
	Address string `json:"address,omitempty" bson:"address,omitempty"`
	// AddressNote is an optional customer/owner-typed landmark description
	// (e.g. "beside Ahmed's kiosk") helping the courier find the pin.
	// Free text, never validated as an address; length-capped at creation.
	AddressNote string `json:"address_note,omitempty" bson:"address_note,omitempty"`
}

// MaxAddressNoteLength caps the free-text landmark note (Option C).
const MaxAddressNoteLength = 500

// ADR-0028 field caps and enum tokens. All v2 booking fields are optional;
// when a value IS provided it must satisfy these bounds.
const (
	MaxAddressLength       = 250 // location.address / destination.address runes
	MaxRecipientNameLength = 100 // recipient.name runes
	MaxRecipientPhoneLen   = 20  // recipient.phone chars (E.164 headroom)
	MaxRecipientNotesLen   = 200 // recipient.notes runes
	MaxPackageNotesLen     = 200 // package_details.notes runes
)

// Sub-status tokens under status == "active" (ADR-0028 §2.4). sub_status
// is defined ONLY while the job is active and is cleared on every exit.
const (
	SubStatusHeadingToPickup = "heading_to_pickup"
	SubStatusPickedUp        = "picked_up"
)

// Allowed package sizes (ADR-0028 §2.7). Informational capacity signal
// only: no pricing effect, backend default is empty/unset.
const (
	PackageSizeSmall  = "small"
	PackageSizeMedium = "medium"
	PackageSizeLarge  = "large"
)

// Actor roles recorded in status_history entries (ADR-0028 §2.3). Admin
// and system actors are sanitized out of the customer/employee DTOs.
const (
	ActorRoleCustomer = "customer"
	ActorRoleEmployee = "employee"
	ActorRoleOwner    = "owner"
	ActorRoleSystem   = "system"
	ActorRoleAdmin    = "admin"
)

// JobRecipient identifies the dropoff recipient when different from the
// booking customer (ADR-0028 §2.1). Written once at booking; never
// client-editable afterwards. Phone exposure on the employee DTO follows
// the acceptance→terminal redaction window (see NewEmployeeJobResponse).
type JobRecipient struct {
	Name  string `json:"name,omitempty"  bson:"name,omitempty"`
	Phone string `json:"phone,omitempty" bson:"phone,omitempty"`
	Notes string `json:"notes,omitempty" bson:"notes,omitempty"`
}

// PackageDetails is an informational capacity descriptor captured at
// booking time (ADR-0028 §2.7). Size never affects pricing.
type PackageDetails struct {
	Size  string `json:"size,omitempty"  bson:"size,omitempty"`
	Notes string `json:"notes,omitempty" bson:"notes,omitempty"`
}

// JobStatusHistoryEntry is one append-only timeline record for a job
// state transition (ADR-0028 §2.3). Server-generated only — never taken
// from client input.
type JobStatusHistoryEntry struct {
	Status    JobStatus `json:"status"               bson:"status"`
	SubStatus string    `json:"sub_status,omitempty" bson:"sub_status,omitempty"`
	At        time.Time `json:"at"                   bson:"at"`
	ActorRole string    `json:"actor_role"           bson:"actor_role"`
	ActorID   string    `json:"actor_id,omitempty"   bson:"actor_id,omitempty"`
	Reason    string    `json:"reason,omitempty"     bson:"reason,omitempty"`
}

// ValidPackageSize reports whether s is an allowed package size token.
// An empty string means "not specified" and is valid.
func ValidPackageSize(s string) bool {
	switch s {
	case "", PackageSizeSmall, PackageSizeMedium, PackageSizeLarge:
		return true
	}
	return false
}

var (
	// Egyptian mobile numbers: optional +20 / leading 0 trunk prefix,
	// then the 1[0,1,2,5] operator prefix and 8 digits (ADR-0028 §2.1).
	egyptianMobilePattern = regexp.MustCompile(`^(?:\+20|0)?1[0125][0-9]{8}$`)
	// Generic E.164: literal +, nonzero country code, 7–14 further digits.
	e164Pattern = regexp.MustCompile(`^\+[1-9][0-9]{7,14}$`)
)

// ValidRecipientPhone reports whether s is an acceptable recipient phone:
// either an Egyptian mobile (with or without country/trunk prefix) or a
// generic E.164 number. Length is additionally capped at
// MaxRecipientPhoneLen before these shapes apply.
func ValidRecipientPhone(s string) bool {
	if len(s) == 0 || len(s) > MaxRecipientPhoneLen {
		return false
	}
	return egyptianMobilePattern.MatchString(s) || e164Pattern.MatchString(s)
}

// etaSpeedKmh is the assumed average urban motorcycle speed used for the
// server-side straight-line ETA snapshot, and etaBufferMin the fixed
// parked/traffic buffer added on top (ADR-0028 §2.5). Named constants so
// the formula stays auditable; no paid routing API backs this estimate.
const (
	etaSpeedKmh  = 20.0
	etaBufferMin = 3
)

// EstimateDurationMinutes maps a straight-line distance (km) to a
// minimum-integer duration estimate: ceil(D / 20 km/h · 60) + 3 min
// buffer. Zero and negative distances still cost the buffer, so a
// co-located courier never yields 0 minutes.
func EstimateDurationMinutes(d float64) int {
	minutes := int(math.Ceil(d / etaSpeedKmh * 60))
	return minutes + etaBufferMin
}

// SanitizeAddressText trims surrounding whitespace and strips control
// characters, leaving the visible text intact for storage/on-read use
// (ADR-0028 §2.2 validation pipeline).
func SanitizeAddressText(s string) string {
	trimmed := strings.TrimSpace(s)
	if trimmed == "" {
		return ""
	}
	clean := make([]rune, 0, len(trimmed))
	for _, r := range trimmed {
		if !unicode.IsControl(r) {
			clean = append(clean, r)
		}
	}
	return string(clean)
}

// Job represents a trackable unit of work linking an owner, employee, and service.
type Job struct {
	ID                       string     `json:"id"                            bson:"_id"`
	OwnerID                  string     `json:"owner_id"                      bson:"owner_id"`
	EmployeeID               string     `json:"employee_id,omitempty"         bson:"employee_id,omitempty"`
	UserID                   string     `json:"user_id"                       bson:"user_id"`
	ServiceID                string     `json:"service_id"                    bson:"service_id"`
	Status                   JobStatus  `json:"status"                        bson:"status"`
	Location                 Location   `json:"location"                      bson:"location"`
	Destination              Location   `json:"destination"                   bson:"destination"`
	CurrentLocation          *Location  `json:"current_location,omitempty"   bson:"current_location,omitempty"`
	Waypoints                []Location `json:"waypoints,omitempty"          bson:"waypoints,omitempty"`
	PaymentMethod            string     `json:"payment_method"                bson:"payment_method"`
	CancellationReason       string     `json:"cancellation_reason,omitempty" bson:"cancellation_reason,omitempty"`
	LockedEscrowAmount       float64    `json:"locked_escrow_amount,omitempty" bson:"locked_escrow_amount,omitempty"`
	ActualCashAmount         *float64   `json:"actual_cash_amount,omitempty"  bson:"actual_cash_amount,omitempty"`
	ReconciliationNote       string     `json:"reconciliation_note,omitempty" bson:"reconciliation_note,omitempty"`
	EscrowFailureReason      string     `json:"escrow_failure_reason,omitempty" bson:"escrow_failure_reason,omitempty"`
	SuggestedPrice           float64    `json:"suggested_price,omitempty"           bson:"suggested_price,omitempty"`
	ProposedPrice            *float64   `json:"proposed_price,omitempty"            bson:"proposed_price,omitempty"`
	ProposedBy               string     `json:"proposed_by,omitempty"               bson:"proposed_by,omitempty"`
	AgreedPrice              *float64   `json:"agreed_price,omitempty"              bson:"agreed_price,omitempty"`
	PriceProposalExpiresAt   *time.Time `json:"price_proposal_expires_at,omitempty" bson:"price_proposal_expires_at,omitempty"`
	BookedDistance           float64    `json:"booked_distance,omitempty"            bson:"booked_distance,omitempty"`
	AssignedEmployeeLocation *Location  `json:"assigned_employee_location,omitempty" bson:"assigned_employee_location,omitempty"`
	CurrentOfferedEmployeeID string     `json:"current_offered_employee_id,omitempty" bson:"current_offered_employee_id,omitempty"`
	OfferExpiresAt           *time.Time `json:"offer_expires_at,omitempty"            bson:"offer_expires_at,omitempty"`
	OfferedEmployeeIDs       []string   `json:"offered_employee_ids,omitempty"        bson:"offered_employee_ids,omitempty"`
	// Employee cancellation request (ADR-0027): the assigned employee asks,
	// the owner approves. Status transitions pending -> approved/rejected,
	// or pending -> expired via lazy expiry. Terminal states persist
	// queryably until superseded by a newer request.
	CancellationRequestReason string     `json:"cancellation_request_reason,omitempty"  bson:"cancellation_request_reason,omitempty"`
	CancellationRequestedAt   *time.Time `json:"cancellation_requested_at,omitempty"    bson:"cancellation_requested_at,omitempty"`
	CancellationRequestStatus string     `json:"cancellation_request_status,omitempty"  bson:"cancellation_request_status,omitempty"`
	CreatedAt                 time.Time  `json:"created_at"                    bson:"created_at"`
	UpdatedAt                 time.Time  `json:"updated_at"                    bson:"updated_at"`
	// DistanceReview is set on a COD delivery/shipping job completed with a
	// tracked GPS distance under the ADR-0007 threshold (FIX-COD-RECON).
	DistanceReview *DistanceReview `json:"distance_review,omitempty" bson:"distance_review,omitempty"`
	// --- Job Model v2 (ADR-0028) ---------------------------------------
	// Recipient, package details, and address text are snapshotted at
	// booking time only; they are never client-editable afterwards.
	Recipient *JobRecipient `json:"recipient,omitempty" bson:"recipient,omitempty"`
	// PackageDetails is informational (capacity signal); size has no
	// pricing effect and defaults to unset (ADR-0028 §2.7).
	PackageDetails *PackageDetails `json:"package_details,omitempty" bson:"package_details,omitempty"`
	// SubStatus refines status == "active" (heading_to_pickup |
	// picked_up). It is set ONLY while the job is active and cleared on
	// every transition out of active; legacy rows simply omit it
	// (ADR-0028 §2.4).
	SubStatus string `json:"sub_status,omitempty" bson:"sub_status,omitempty"`
	// StatusHistory is the append-only transition timeline. Appended
	// server-side in the same MongoDB update as each transition via $push;
	// never synthesized for legacy rows (lazy on-read) (ADR-0028 §2.3).
	StatusHistory []JobStatusHistoryEntry `json:"status_history,omitempty" bson:"status_history,omitempty"`
	// EstimatedDurationMinutes is the server-side straight-line ETA
	// snapshot taken at acceptance (courier→pickup) and again at pickup
	// (courier→destination); nil when no fresh courier location exists
	// (ADR-0028 §2.5).
	EstimatedDurationMinutes *int `json:"estimated_duration_minutes,omitempty" bson:"estimated_duration_minutes,omitempty"`
	// CustomerName snapshots the booking customer's display name for owners.
	CustomerName string `json:"customer_name,omitempty" bson:"customer_name,omitempty"`
}

// DistanceReview is an owner-facing review flag for a cash-on-delivery job
// whose tracked GPS distance was under 70 % of the booked distance (ADR-0007
// under-distance check). Unlike the non-COD path, the job still completes and
// the collected cash is recorded: no platform money is held, so there is
// nothing to release or refund (FIX-COD-RECON). Source says what set it.
type DistanceReview struct {
	ActualKm  float64   `json:"actual_km"        bson:"actual_km"`
	BookedKm  float64   `json:"booked_km"        bson:"booked_km"`
	FlaggedAt time.Time `json:"flagged_at"       bson:"flagged_at"`
	Source    string    `json:"source,omitempty" bson:"source,omitempty"`
}

// DistanceReview sources. A stuck_job_repair flag was set by the
// --repair-stuck-cod-reconciliation-jobs CLI for a job parked before the
// fix: its actual_cash_amount is the booked amount, not a courier entry.
const (
	DistanceReviewSourceCompleteJob = "complete_job"
	DistanceReviewSourceRepair      = "stuck_job_repair"
)

// OwnerJobResponse provides full tenant job visibility for business owners.
type OwnerJobResponse struct {
	ID                        string     `json:"id"`
	OwnerID                   string     `json:"owner_id"`
	ServiceID                 string     `json:"service_id"`
	UserID                    string     `json:"user_id"`
	EmployeeID                string     `json:"employee_id,omitempty"`
	CurrentOfferedEmployeeID  string     `json:"current_offered_employee_id,omitempty"`
	OfferExpiresAt            *time.Time `json:"offer_expires_at,omitempty"`
	OfferedEmployeeIDs        []string   `json:"offered_employee_ids,omitempty"`
	CancellationRequestReason string     `json:"cancellation_request_reason,omitempty"`
	CancellationRequestedAt   *time.Time `json:"cancellation_requested_at,omitempty"`
	CancellationRequestStatus string     `json:"cancellation_request_status,omitempty"`
	Status                    JobStatus  `json:"status"`
	Location                  Location   `json:"location"`
	Destination               Location   `json:"destination"`
	CurrentLocation           *Location  `json:"current_location,omitempty"`
	PaymentMethod             string     `json:"payment_method"`
	CancellationReason        string     `json:"cancellation_reason,omitempty"`
	LockedEscrowAmount        float64    `json:"locked_escrow_amount,omitempty"`
	ActualCashAmount          *float64   `json:"actual_cash_amount,omitempty"`
	ReconciliationNote        string     `json:"reconciliation_note,omitempty"`
	EscrowFailureReason       string     `json:"escrow_failure_reason,omitempty"`
	SuggestedPrice            float64    `json:"suggested_price,omitempty"`
	ProposedPrice             *float64   `json:"proposed_price,omitempty"`
	ProposedBy                string     `json:"proposed_by,omitempty"`
	AgreedPrice               *float64   `json:"agreed_price,omitempty"`
	PriceProposalExpiresAt    *time.Time `json:"price_proposal_expires_at,omitempty"`
	CreatedAt                 time.Time  `json:"created_at"`
	UpdatedAt                 time.Time  `json:"updated_at"`
	// DistanceReview is the owner-only COD under-distance review flag
	// (FIX-COD-RECON); omitted when the job was not flagged.
	DistanceReview *DistanceReview `json:"distance_review,omitempty"`
	// --- Job Model v2 (ADR-0028 §3.4) ----------------------------------
	// Recipient/package/address/eta/history are pure projections of the
	// stored job. CourierPhone is NOT filled by this constructor: it
	// requires a live auth-service lookup, so handlers overlay it for
	// eligible roles (empty ⇒ omitted ⇒ redacted).
	Recipient                *JobRecipient           `json:"recipient,omitempty"`
	PackageDetails           *PackageDetails         `json:"package_details,omitempty"`
	SubStatus                string                  `json:"sub_status,omitempty"`
	StatusHistory            []JobStatusHistoryEntry `json:"status_history,omitempty"`
	EstimatedDurationMinutes *int                    `json:"estimated_duration_minutes,omitempty"`
	CourierPhone             string                  `json:"courier_phone,omitempty"`
	CustomerName             string                  `json:"customer_name,omitempty"`
}

// NewOwnerJobResponse maps a Job struct to an OwnerJobResponse DTO.
func NewOwnerJobResponse(j *Job) OwnerJobResponse {
	if j == nil {
		return OwnerJobResponse{}
	}
	return OwnerJobResponse{
		ID:                        j.ID,
		OwnerID:                   j.OwnerID,
		ServiceID:                 j.ServiceID,
		UserID:                    j.UserID,
		CustomerName:              j.CustomerName,
		EmployeeID:                j.EmployeeID,
		CurrentOfferedEmployeeID:  j.CurrentOfferedEmployeeID,
		OfferExpiresAt:            j.OfferExpiresAt,
		OfferedEmployeeIDs:        j.OfferedEmployeeIDs,
		CancellationRequestReason: j.CancellationRequestReason,
		CancellationRequestedAt:   j.CancellationRequestedAt,
		CancellationRequestStatus: j.CancellationRequestStatus,
		Status:                    j.Status,
		Location:                  j.Location,
		Destination:               j.Destination,
		CurrentLocation:           j.CurrentLocation,
		PaymentMethod:             j.PaymentMethod,
		CancellationReason:        j.CancellationReason,
		LockedEscrowAmount:        j.LockedEscrowAmount,
		ActualCashAmount:          j.ActualCashAmount,
		ReconciliationNote:        j.ReconciliationNote,
		EscrowFailureReason:       j.EscrowFailureReason,
		SuggestedPrice:            j.SuggestedPrice,
		ProposedPrice:             j.ProposedPrice,
		ProposedBy:                j.ProposedBy,
		AgreedPrice:               j.AgreedPrice,
		PriceProposalExpiresAt:    j.PriceProposalExpiresAt,
		CreatedAt:                 j.CreatedAt,
		UpdatedAt:                 j.UpdatedAt,
		DistanceReview:            j.DistanceReview,
		Recipient:                 j.Recipient,
		PackageDetails:            j.PackageDetails,
		SubStatus:                 v2SubStatusForDTO(j),
		StatusHistory:             j.StatusHistory,
		EstimatedDurationMinutes:  j.EstimatedDurationMinutes,
	}
}

// CustomerJobResponse provides job booking history for customers, excluding internal tenant & financial fields.
type CustomerJobResponse struct {
	ID                     string     `json:"id"`
	ServiceID              string     `json:"service_id"`
	EmployeeID             string     `json:"employee_id,omitempty"`
	Status                 JobStatus  `json:"status"`
	Location               Location   `json:"location"`
	Destination            Location   `json:"destination"`
	CurrentLocation        *Location  `json:"current_location,omitempty"`
	PaymentMethod          string     `json:"payment_method"`
	CancellationReason     string     `json:"cancellation_reason,omitempty"`
	SuggestedPrice         float64    `json:"suggested_price,omitempty"`
	ProposedPrice          *float64   `json:"proposed_price,omitempty"`
	ProposedBy             string     `json:"proposed_by,omitempty"`
	AgreedPrice            *float64   `json:"agreed_price,omitempty"`
	PriceProposalExpiresAt *time.Time `json:"price_proposal_expires_at,omitempty"`
	CreatedAt              time.Time  `json:"created_at"`
	UpdatedAt              time.Time  `json:"updated_at"`
	// --- Job Model v2 (ADR-0028 §3.4) ----------------------------------
	// Recipient is the booking customer's data and is always exposed to
	// them. CourierPhone is overlaid by handlers during the active window
	// only (S2S auth-service fetch); empty here ⇒ omitted ⇒ redacted.
	Recipient                *JobRecipient           `json:"recipient,omitempty"`
	PackageDetails           *PackageDetails         `json:"package_details,omitempty"`
	SubStatus                string                  `json:"sub_status,omitempty"`
	StatusHistory            []JobStatusHistoryEntry `json:"status_history,omitempty"`
	EstimatedDurationMinutes *int                    `json:"estimated_duration_minutes,omitempty"`
	CourierPhone             string                  `json:"courier_phone,omitempty"`
}

// NewCustomerJobResponse maps a Job struct to a CustomerJobResponse DTO.
func NewCustomerJobResponse(j *Job) CustomerJobResponse {
	if j == nil {
		return CustomerJobResponse{}
	}
	return CustomerJobResponse{
		ID:                       j.ID,
		ServiceID:                j.ServiceID,
		EmployeeID:               j.EmployeeID,
		Status:                   j.Status,
		Location:                 j.Location,
		Destination:              j.Destination,
		CurrentLocation:          j.CurrentLocation,
		PaymentMethod:            j.PaymentMethod,
		CancellationReason:       j.CancellationReason,
		SuggestedPrice:           j.SuggestedPrice,
		ProposedPrice:            j.ProposedPrice,
		ProposedBy:               j.ProposedBy,
		AgreedPrice:              j.AgreedPrice,
		PriceProposalExpiresAt:   j.PriceProposalExpiresAt,
		CreatedAt:                j.CreatedAt,
		UpdatedAt:                j.UpdatedAt,
		Recipient:                j.Recipient,
		PackageDetails:           j.PackageDetails,
		SubStatus:                v2SubStatusForDTO(j),
		StatusHistory:            SanitizeStatusHistoryForParticipant(j.StatusHistory),
		EstimatedDurationMinutes: j.EstimatedDurationMinutes,
	}
}

// EmployeeJobResponse provides job detail for assigned or candidate employees,
// excluding internal reconciliation notes, escrow failure details, and other candidates' IDs.
type EmployeeJobResponse struct {
	ID                        string     `json:"id"`
	OwnerID                   string     `json:"owner_id"`
	ServiceID                 string     `json:"service_id"`
	UserID                    string     `json:"user_id"`
	EmployeeID                string     `json:"employee_id,omitempty"`
	CurrentOfferedEmployeeID  string     `json:"current_offered_employee_id,omitempty"`
	OfferExpiresAt            *time.Time `json:"offer_expires_at,omitempty"`
	Status                    JobStatus  `json:"status"`
	Location                  Location   `json:"location"`
	Destination               Location   `json:"destination"`
	CurrentLocation           *Location  `json:"current_location,omitempty"`
	PaymentMethod             string     `json:"payment_method"`
	CancellationReason        string     `json:"cancellation_reason,omitempty"`
	LockedEscrowAmount        float64    `json:"locked_escrow_amount,omitempty"`
	CancellationRequestReason string     `json:"cancellation_request_reason,omitempty"`
	CancellationRequestedAt   *time.Time `json:"cancellation_requested_at,omitempty"`
	CancellationRequestStatus string     `json:"cancellation_request_status,omitempty"`
	// A6: no ActualCashAmount — owner/reconciliation-only, never sent to employees.
	SuggestedPrice         float64    `json:"suggested_price,omitempty"`
	ProposedPrice          *float64   `json:"proposed_price,omitempty"`
	ProposedBy             string     `json:"proposed_by,omitempty"`
	AgreedPrice            *float64   `json:"agreed_price,omitempty"`
	PriceProposalExpiresAt *time.Time `json:"price_proposal_expires_at,omitempty"`
	CreatedAt              time.Time  `json:"created_at"`
	UpdatedAt              time.Time  `json:"updated_at"`
	// --- Job Model v2 (ADR-0028 §3.4) ----------------------------------
	// Recipient name/notes stay visible, but the phone follows the
	// acceptance→terminal redaction window (see the constructor). No
	// courier_phone here — the employee IS the courier (N/A self).
	Recipient                *JobRecipient           `json:"recipient,omitempty"`
	PackageDetails           *PackageDetails         `json:"package_details,omitempty"`
	SubStatus                string                  `json:"sub_status,omitempty"`
	StatusHistory            []JobStatusHistoryEntry `json:"status_history,omitempty"`
	EstimatedDurationMinutes *int                    `json:"estimated_duration_minutes,omitempty"`
}

// NewEmployeeJobResponse maps a Job struct to an EmployeeJobResponse DTO,

// NewEmployeeJobResponse maps a Job struct to an EmployeeJobResponse DTO,
// scoped to the requester's employee identity.
func NewEmployeeJobResponse(j *Job, requesterEmployeeID string) EmployeeJobResponse {
	if j == nil {
		return EmployeeJobResponse{}
	}
	resp := EmployeeJobResponse{
		ID:                        j.ID,
		OwnerID:                   j.OwnerID,
		ServiceID:                 j.ServiceID,
		UserID:                    j.UserID,
		EmployeeID:                j.EmployeeID,
		Status:                    j.Status,
		Location:                  j.Location,
		Destination:               j.Destination,
		CurrentLocation:           j.CurrentLocation,
		PaymentMethod:             j.PaymentMethod,
		CancellationReason:        j.CancellationReason,
		LockedEscrowAmount:        j.LockedEscrowAmount,
		CancellationRequestReason: j.CancellationRequestReason,
		CancellationRequestedAt:   j.CancellationRequestedAt,
		CancellationRequestStatus: j.CancellationRequestStatus,
		// A6: ActualCashAmount is owner/reconciliation-only (Flutter
		// employee screens never read it) — excluded from the employee DTO.
		SuggestedPrice:           j.SuggestedPrice,
		ProposedPrice:            j.ProposedPrice,
		ProposedBy:               j.ProposedBy,
		AgreedPrice:              j.AgreedPrice,
		PriceProposalExpiresAt:   j.PriceProposalExpiresAt,
		CreatedAt:                j.CreatedAt,
		UpdatedAt:                j.UpdatedAt,
		Recipient:                v2RecipientForEmployee(j),
		PackageDetails:           j.PackageDetails,
		SubStatus:                v2SubStatusForDTO(j),
		StatusHistory:            SanitizeStatusHistoryForParticipant(j.StatusHistory),
		EstimatedDurationMinutes: j.EstimatedDurationMinutes,
	}
	if j.CurrentOfferedEmployeeID != "" && j.CurrentOfferedEmployeeID == requesterEmployeeID {
		resp.CurrentOfferedEmployeeID = j.CurrentOfferedEmployeeID
		resp.OfferExpiresAt = j.OfferExpiresAt
	}
	return resp
}

// v2SubStatusForDTO projects SubStatus only for active jobs. sub_status is
// defined strictly under status == "active" (ADR-0028 §2.4); a defensive
// clear here keeps terminal rows from ever echoing a stale phase even if
// data were written before the guard shipped.
func v2SubStatusForDTO(j *Job) string {
	if j.Status != JobStatusActive {
		return ""
	}
	return j.SubStatus
}

// v2RecipientForEmployee applies the employee-side recipient redaction
// window (ADR-0028 §2.1/§2.9): while the job is active the courier sees
// the full recipient (on-trip contact need). Once the job leaves active
// — completed, cancelled, unavailable, reconciliation review — the phone
// is redacted while name/notes survive for record-keeping. Jobs without
// a recipient (legacy bookings) pass through as nil.
func v2RecipientForEmployee(j *Job) *JobRecipient {
	if j.Recipient == nil {
		return nil
	}
	redacted := *j.Recipient
	if j.Status != JobStatusActive {
		redacted.Phone = ""
	}
	return &redacted
}

// SanitizeStatusHistoryForParticipant strips audit actor IDs from timeline
// entries whose actor is an internal operator (admin reviewer) or an
// automated backend process (system), for the customer/employee DTOs
// (ADR-0028 §2.3 privacy note). Owner/admin views keep full IDs.
func SanitizeStatusHistoryForParticipant(h []JobStatusHistoryEntry) []JobStatusHistoryEntry {
	if h == nil {
		return nil
	}
	out := make([]JobStatusHistoryEntry, len(h))
	copy(out, h)
	for i := range out {
		switch out[i].ActorRole {
		case ActorRoleAdmin, ActorRoleSystem:
			out[i].ActorID = ""
		}
	}
	return out
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

// WalletResponse is the client-facing wallet projection (A6): balances
// plus timestamp only. The internal id/tenant echoes are stripped — the
// caller already knows its own tenant.
type WalletResponse struct {
	TotalBalance        float64   `json:"total_balance"`
	EscrowBalance       float64   `json:"escrow_balance"`
	WithdrawableBalance float64   `json:"withdrawable_balance"`
	UpdatedAt           time.Time `json:"updated_at"`
}

// NewWalletResponse projects a stored wallet to its client-safe shape.
func NewWalletResponse(w *Wallet) WalletResponse {
	if w == nil {
		return WalletResponse{}
	}
	return WalletResponse{
		TotalBalance:        w.TotalBalance,
		EscrowBalance:       w.EscrowBalance,
		WithdrawableBalance: w.WithdrawableBalance,
		UpdatedAt:           w.UpdatedAt,
	}
}

// LedgerEntryResponse is the client-facing ledger projection (A6): only
// the fields the wallet/history screens render. The id/tenant echoes and
// balance_before (reconstructible from neighbors) are stripped.
type LedgerEntryResponse struct {
	JobID        string          `json:"job_id"`
	Type         TransactionType `json:"type"`
	Amount       float64         `json:"amount"`
	BalanceAfter float64         `json:"balance_after"`
	Description  string          `json:"description"`
	Timestamp    time.Time       `json:"timestamp"`
}

// NewLedgerEntryResponse projects a stored entry to its client-safe shape.
func NewLedgerEntryResponse(e TransactionLedger) LedgerEntryResponse {
	return LedgerEntryResponse{
		JobID:        e.JobID,
		Type:         e.Type,
		Amount:       e.Amount,
		BalanceAfter: e.BalanceAfter,
		Description:  e.Description,
		Timestamp:    e.Timestamp,
	}
}

// TransactionType defines the kind of ledger entry.
type TransactionType string

const (
	TxEscrowLock    TransactionType = "escrow_lock"
	TxEscrowRelease TransactionType = "escrow_release"
	TxPlatformFee   TransactionType = "platform_fee"
	TxPayout        TransactionType = "payout"
	TxPayoutRefund  TransactionType = "payout_refund"
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

// PayoutStatus defines the lifecycle status of an owner payout/withdrawal request.
type PayoutStatus string

const (
	PayoutStatusRequested PayoutStatus = "requested"
	PayoutStatusApproved  PayoutStatus = "approved"
	PayoutStatusRejected  PayoutStatus = "rejected"
	PayoutStatusPaid      PayoutStatus = "paid"
)

// PayoutRequest represents a tenant owner's withdrawal request from withdrawable_balance.
type PayoutRequest struct {
	ID              string       `json:"id"               bson:"_id"`
	TenantID        string       `json:"tenant_id"        bson:"tenant_id"`
	Amount          float64      `json:"amount"           bson:"amount"`
	Status          PayoutStatus `json:"status"           bson:"status"`
	PayoutMethod    string       `json:"payout_method"    bson:"payout_method"` // e.g. "bank_transfer", "instapay"
	AccountDetails  string       `json:"account_details,omitempty" bson:"account_details,omitempty"`
	RejectionReason string       `json:"rejection_reason,omitempty" bson:"rejection_reason,omitempty"`
	CreatedAt       time.Time    `json:"created_at"       bson:"created_at"`
	UpdatedAt       time.Time    `json:"updated_at"       bson:"updated_at"`
}

// CreatePayoutRequestInput is the expected JSON payload for POST /users/wallet/payout/request.
type CreatePayoutRequestInput struct {
	TenantID       string  `json:"tenant_id,omitempty"`
	TenantToken    string  `json:"tenant_token,omitempty"`
	Amount         float64 `json:"amount"`
	PayoutMethod   string  `json:"payout_method"`
	AccountDetails string  `json:"account_details,omitempty"`
	// IdempotencyKey optionally identifies this logical request across
	// network retries; the Idempotency-Key header takes precedence.
	IdempotencyKey string `json:"idempotency_key,omitempty"`
}

// ---------------------------------------------------------------------------
// Request / Response types
// ---------------------------------------------------------------------------

// CreateServiceRequest is the expected JSON body for POST /users/services.
type CreateServiceRequest struct {
	OwnerID          string        `json:"owner_id"`
	OwnerToken       string        `json:"owner_token,omitempty"`
	Name             string        `json:"name"`
	Category         string        `json:"category"`
	TenantBasePrice  float64       `json:"tenant_base_price"`
	TenantPricePerKM float64       `json:"tenant_price_per_km"`
	Latitude         float64       `json:"latitude"`
	Longitude        float64       `json:"longitude"`
	PhotoURL         string        `json:"photo_url,omitempty"`
	Photo            string        `json:"photo,omitempty"`
	Address          string        `json:"address,omitempty"`
	WorkingHours     string        `json:"working_hours,omitempty"`
	CoverageRadiusKM float64       `json:"coverage_radius_km,omitempty"`
	CoverageRadius   float64       `json:"coverage_radius,omitempty"`
	ScheduleMode     string        `json:"schedule_mode,omitempty"`
	OpenTime         string        `json:"open_time,omitempty"`
	CloseTime        string        `json:"close_time,omitempty"`
	PerDaySchedule   []DaySchedule `json:"per_day_schedule,omitempty"`
	Timezone         string        `json:"timezone,omitempty"`
}

// UpdateServiceRequest is the expected JSON body for PUT/PATCH /users/services or POST /users/services/update.
type UpdateServiceRequest struct {
	ID               string         `json:"id"`
	ServiceID        string         `json:"service_id,omitempty"`
	OwnerID          string         `json:"owner_id"`
	OwnerToken       string         `json:"owner_token,omitempty"`
	Name             string         `json:"name,omitempty"`
	Category         string         `json:"category,omitempty"`
	TenantBasePrice  *float64       `json:"tenant_base_price,omitempty"`
	TenantPricePerKM *float64       `json:"tenant_price_per_km,omitempty"`
	Latitude         *float64       `json:"latitude,omitempty"`
	Longitude        *float64       `json:"longitude,omitempty"`
	PhotoURL         *string        `json:"photo_url,omitempty"`
	Photo            *string        `json:"photo,omitempty"`
	Address          *string        `json:"address,omitempty"`
	WorkingHours     *string        `json:"working_hours,omitempty"`
	CoverageRadiusKM *float64       `json:"coverage_radius_km,omitempty"`
	CoverageRadius   *float64       `json:"coverage_radius,omitempty"`
	ScheduleMode     *string        `json:"schedule_mode,omitempty"`
	OpenTime         *string        `json:"open_time,omitempty"`
	CloseTime        *string        `json:"close_time,omitempty"`
	PerDaySchedule   *[]DaySchedule `json:"per_day_schedule,omitempty"`
	Timezone         *string        `json:"timezone,omitempty"`
}

// CreateJobRequest is the expected JSON body for POST /users/jobs/track.
type CreateJobRequest struct {
	OwnerID        string    `json:"owner_id"`
	OwnerToken     string    `json:"owner_token,omitempty"`
	EmployeeID     string    `json:"employee_id,omitempty"`
	EmployeeToken  string    `json:"employee_token,omitempty"`
	ServiceID      string    `json:"service_id"`
	Location       Location  `json:"location"`
	Destination    *Location `json:"destination"`
	PaymentMethod  string    `json:"payment_method"`
	UserID         string    `json:"user_id"`
	UserToken      string    `json:"user_token,omitempty"`
	IdempotencyKey string    `json:"idempotency_key,omitempty"`
	ProposedPrice  *float64  `json:"proposed_price,omitempty"`
	// ADR-0028 v2 booking inputs. Optional: absent stays absent. Once
	// persisted they are snapshotted and never client-editable.
	Recipient      *JobRecipient   `json:"recipient,omitempty"`
	PackageDetails *PackageDetails `json:"package_details,omitempty"`
}

// DepositRequest is the expected JSON body for POST /users/wallet/deposit.
type DepositRequest struct {
	TenantID    string  `json:"tenant_id"`
	TenantToken string  `json:"tenant_token,omitempty"`
	Amount      float64 `json:"amount"`
}

// CompleteJobRequest is the expected JSON body for POST /users/jobs/complete.
type CompleteJobRequest struct {
	JobID         string `json:"job_id"`
	CashCollected bool   `json:"cash_collected"`
	// ActualCashAmount is the employee-reported cash actually collected for
	// COD jobs. When >0 it is cent-rounded and persisted on the job record;
	// otherwise the agreed/recomputed amount is recorded as before.
	ActualCashAmount float64 `json:"actual_cash_amount,omitempty"`
	RequesterID      string  `json:"requester_id"`
	RequesterToken   string  `json:"requester_token,omitempty"`
}

type PlanTier string

const (
	PlanFree           PlanTier = "free"
	PlanPaid           PlanTier = "paid"
	PlanPendingPayment PlanTier = "pending_payment"
	PlanCancelled      PlanTier = "cancelled"
)

type Subscription struct {
	ID          string    `json:"id"                     bson:"_id"`
	TenantID    string    `json:"tenant_id"              bson:"tenant_id"`
	Tier        PlanTier  `json:"tier"                   bson:"tier"`
	StartedAt   time.Time `json:"started_at"             bson:"started_at"`
	ExpiresAt   time.Time `json:"expires_at,omitempty"   bson:"expires_at,omitempty"`   // zero = no expiry (free tier)
	Reason      string    `json:"reason,omitempty"       bson:"reason,omitempty"`       // revocation or activation note
	ActivatedBy string    `json:"activated_by,omitempty" bson:"activated_by,omitempty"` // reviewer ID
	RevokedBy   string    `json:"revoked_by,omitempty"   bson:"revoked_by,omitempty"`   // reviewer ID
	UpdatedAt   time.Time `json:"updated_at,omitempty"   bson:"updated_at,omitempty"`
}

// SubscriptionResponse is the client-facing subscription projection (A6):
// tier plus lifecycle timestamps only. Internal id/tenant echoes and
// reviewer audit fields (reason/activated_by/revoked_by) are stripped —
// the admin reviewer console reads those via admin endpoints.
type SubscriptionResponse struct {
	Tier      PlanTier  `json:"tier"`
	StartedAt time.Time `json:"started_at"`
	ExpiresAt time.Time `json:"expires_at,omitempty"`
	UpdatedAt time.Time `json:"updated_at,omitempty"`
}

// NewSubscriptionResponse projects a stored subscription to its
// client-safe shape.
func NewSubscriptionResponse(s *Subscription) SubscriptionResponse {
	if s == nil {
		return SubscriptionResponse{}
	}
	return SubscriptionResponse{
		Tier:      s.Tier,
		StartedAt: s.StartedAt,
		ExpiresAt: s.ExpiresAt,
		UpdatedAt: s.UpdatedAt,
	}
}

// IsClosed reports whether a tenant is closed for public marketplace purposes
// (ADR-0024): missing subscription, non-paid tier, or past ExpiresAt.
// Zero ExpiresAt keeps its documented meaning ("zero = no expiry") and stays
// open while the tier is paid. Nil-safe: a nil subscription is closed.
// This is the single definition of closed — requireTier, ListServices
// filtering, and the TrackJob booking gate all delegate to it.
func (s *Subscription) IsClosed(now time.Time) bool {
	if s == nil {
		return true
	}
	if s.Tier != PlanPaid {
		return true
	}
	if !s.ExpiresAt.IsZero() && now.After(s.ExpiresAt) {
		return true
	}
	return false
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

// EmployeeLocation represents an employee's last reported location and availability timestamp.
type EmployeeLocation struct {
	TenantID    string    `json:"tenant_id"     bson:"tenant_id"`
	EmployeeID  string    `json:"employee_id"   bson:"employee_id"`
	Latitude    float64   `json:"latitude"      bson:"latitude"`
	Longitude   float64   `json:"longitude"     bson:"longitude"`
	UpdatedAt   time.Time `json:"updated_at"    bson:"updated_at"`
	ActiveJobID string    `json:"active_job_id,omitempty" bson:"active_job_id,omitempty"`
}

// EmployeeLocationPingRequest is the expected JSON body for POST /users/employee/location.
type EmployeeLocationPingRequest struct {
	RequesterID    string  `json:"requester_id,omitempty"`
	RequesterToken string  `json:"requester_token,omitempty"`
	Latitude       float64 `json:"latitude"`
	Longitude      float64 `json:"longitude"`
}

// AdminReconciliationJobItem represents a disputed delivery/job in the ops reconciliation queue (ADR-0023).
type AdminReconciliationJobItem struct {
	ID                   string    `json:"id"`
	TenantID             string    `json:"tenant_id"`
	OwnerID              string    `json:"owner_id"`
	EmployeeID           string    `json:"employee_id,omitempty"`
	CustomerID           string    `json:"customer_id"`
	ServiceID            string    `json:"service_id"`
	BookedDistance       float64   `json:"booked_distance"`
	ActualDistance       float64   `json:"actual_distance"`
	WaypointsCount       int       `json:"waypoints_count"`
	LockedEscrowAmount   float64   `json:"locked_escrow_amount"`
	ActualAmount         float64   `json:"actual_amount"`
	PaymentMethod        string    `json:"payment_method"`
	Status               JobStatus `json:"status"`
	ReconciliationNote   string    `json:"reconciliation_note"`
	ReconciliationReason string    `json:"reconciliation_reason"`
	CreatedAt            time.Time `json:"created_at"`
	UpdatedAt            time.Time `json:"updated_at"`
}

// AdminReconciliationQueueResponse is the payload returned by GET /admin/reconciliation/queue.
type AdminReconciliationQueueResponse struct {
	Disputes []AdminReconciliationJobItem `json:"disputes"`
	Total    int                          `json:"total"`
	Page     int                          `json:"page"`
	Limit    int                          `json:"limit"`
}

// AdminResolveReconciliationRequest is the payload for POST /admin/reconciliation/resolve.
type AdminResolveReconciliationRequest struct {
	JobID    string `json:"job_id"`
	Decision string `json:"decision"` // "release_to_employee" or "refund_to_customer"
	Reason   string `json:"reason"`   // Mandatory reason (1-1000 characters)
}

// AdminSubscriptionListResponse is the payload returned by GET /admin/subscriptions.
type AdminSubscriptionListResponse struct {
	Subscriptions []Subscription `json:"subscriptions"`
	Total         int            `json:"total"`
	Page          int            `json:"page"`
	Limit         int            `json:"limit"`
}

// AdminActivateSubscriptionRequest is the payload for POST /admin/subscriptions/activate.
type AdminActivateSubscriptionRequest struct {
	TenantID       string `json:"tenant_id"`
	SubscriptionID string `json:"subscription_id,omitempty"`
	DurationDays   int    `json:"duration_days,omitempty"` // Defaults to 30 days if <= 0
}

// AdminRevokeSubscriptionRequest is the payload for POST /admin/subscriptions/revoke.
type AdminRevokeSubscriptionRequest struct {
	TenantID       string `json:"tenant_id"`
	SubscriptionID string `json:"subscription_id,omitempty"`
	Reason         string `json:"reason"` // Mandatory reason (1-1000 characters)
}

// AdminRejectPayoutRequest is the payload for POST /admin/payouts/reject.
type AdminRejectPayoutRequest struct {
	PayoutID string `json:"payout_id"`
	Reason   string `json:"reason"` // Mandatory reason (1-1000 characters)
}

// AdminPayoutListResponse is the payload returned by GET /admin/payouts.
type AdminPayoutListResponse struct {
	Payouts []*PayoutRequest `json:"payouts"`
	Total   int              `json:"total"`
	Page    int              `json:"page"`
	Limit   int              `json:"limit"`
}
