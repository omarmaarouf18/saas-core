// Package store provides an in-memory data store for the user-service.
// This replaces persistent DB calls until schemas are finalized.
package store

import (
	"fmt"
	"math"
	"sort"
	"sync"

	"github.com/project/user-service/internal/models"
)

// Memory is a thread-safe in-memory store for services and jobs.
type Memory struct {
	mu       sync.RWMutex
	services []models.Service       // pre-seeded service catalog
	jobs     map[string]*models.Job // keyed by job ID
}

// NewMemory creates a store pre-seeded with sample services for testing.
func NewMemory() *Memory {
	return &Memory{
		services: seedServices(),
		jobs:     make(map[string]*models.Job),
	}
}

// ---------------------------------------------------------------------------
// Service operations
// ---------------------------------------------------------------------------

// CreateService adds a new service to the catalog.
func (m *Memory) CreateService(svc *models.Service) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.services = append(m.services, *svc)
}

// ListServices returns all services with dynamically computed tenant pricing,
// optionally sorted by final price and/or filtered by proximity.
//
// Pricing formula:
//
//	FinalPrice = TenantBasePrice + (DistanceInKM × TenantPricePerKM)
//
// Parameters:
//   - sortBy:     "price" to sort ascending by FinalPrice; empty for natural order
//   - nearBy:     if true, filter to services within maxDistKm of (refLat, refLon)
//   - refLat/Lon: reference coordinates for distance calculation
//   - maxDistKm:  maximum distance in kilometres (default 50 km if ≤ 0)
func (m *Memory) ListServices(sortBy string, nearBy bool, refLat, refLon, maxDistKm float64) []models.ServiceWithPrice {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Build enriched results with distance and tenant-formula pricing.
	var result []models.ServiceWithPrice
	for _, svc := range m.services {
		dist := haversineKm(refLat, refLon, svc.Latitude, svc.Longitude)

		// Proximity filter.
		if nearBy {
			if maxDistKm <= 0 {
				maxDistKm = 50
			}
			if dist > maxDistKm {
				continue
			}
		}

		// Tenant dynamic pricing: FinalPrice = TenantBasePrice + (dist × TenantPricePerKM)
		finalPrice := svc.TenantBasePrice + (dist * svc.TenantPricePerKM)

		// Round to 2 decimal places for currency display.
		finalPrice = math.Round(finalPrice*100) / 100
		dist = math.Round(dist*100) / 100

		result = append(result, models.ServiceWithPrice{
			Service:    svc,
			DistanceKM: dist,
			FinalPrice: finalPrice,
		})
	}

	// Sort by computed FinalPrice (tenant-aware).
	if sortBy == "price" {
		sort.Slice(result, func(i, j int) bool {
			return result[i].FinalPrice < result[j].FinalPrice
		})
	}

	return result
}

// ---------------------------------------------------------------------------
// Job operations
// ---------------------------------------------------------------------------

// CreateJob stores a new job and returns a copy.
func (m *Memory) CreateJob(job *models.Job) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if _, exists := m.jobs[job.ID]; exists {
		return fmt.Errorf("job %q already exists", job.ID)
	}
	m.jobs[job.ID] = job
	return nil
}

// GetJob retrieves a job by ID. Returns nil if not found.
func (m *Memory) GetJob(id string) *models.Job {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.jobs[id]
}

// UpdateJobStatus transitions a job to the given status.
func (m *Memory) UpdateJobStatus(id string, status models.JobStatus) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	job, exists := m.jobs[id]
	if !exists {
		return fmt.Errorf("job %q not found", id)
	}
	job.Status = status
	return nil
}

// ListJobs returns all stored jobs (unordered).
func (m *Memory) ListJobs() []*models.Job {
	m.mu.RLock()
	defer m.mu.RUnlock()

	result := make([]*models.Job, 0, len(m.jobs))
	for _, j := range m.jobs {
		result = append(result, j)
	}
	return result
}

// ---------------------------------------------------------------------------
// Seed data
// ---------------------------------------------------------------------------

func seedServices() []models.Service {
	return []models.Service{
		{ID: "svc-001", Name: "Home Cleaning", Category: "Cleaning", BasePrice: 45.00, TenantBasePrice: 40.00, TenantPricePerKM: 2.50, Latitude: 30.0444, Longitude: 31.2357},
		{ID: "svc-002", Name: "Office Deep Clean", Category: "Cleaning", BasePrice: 120.00, TenantBasePrice: 100.00, TenantPricePerKM: 5.00, Latitude: 30.0500, Longitude: 31.2400},
		{ID: "svc-003", Name: "Plumbing Repair", Category: "Maintenance", BasePrice: 75.00, TenantBasePrice: 65.00, TenantPricePerKM: 3.00, Latitude: 30.0600, Longitude: 31.2200},
		{ID: "svc-004", Name: "Electrical Wiring", Category: "Maintenance", BasePrice: 90.00, TenantBasePrice: 80.00, TenantPricePerKM: 4.00, Latitude: 30.0800, Longitude: 31.2100},
		{ID: "svc-005", Name: "Lawn Mowing", Category: "Gardening", BasePrice: 35.00, TenantBasePrice: 30.00, TenantPricePerKM: 1.50, Latitude: 30.1000, Longitude: 31.3000},
		{ID: "svc-006", Name: "Tree Trimming", Category: "Gardening", BasePrice: 60.00, TenantBasePrice: 50.00, TenantPricePerKM: 2.00, Latitude: 30.1200, Longitude: 31.3200},
		{ID: "svc-007", Name: "AC Maintenance", Category: "HVAC", BasePrice: 110.00, TenantBasePrice: 95.00, TenantPricePerKM: 3.50, Latitude: 31.2001, Longitude: 29.9187},
		{ID: "svc-008", Name: "Pest Control", Category: "Cleaning", BasePrice: 55.00, TenantBasePrice: 45.00, TenantPricePerKM: 2.00, Latitude: 31.2100, Longitude: 29.9250},
		{ID: "svc-009", Name: "Painting", Category: "Renovation", BasePrice: 200.00, TenantBasePrice: 180.00, TenantPricePerKM: 6.00, Latitude: 29.9792, Longitude: 31.1342},
		{ID: "svc-010", Name: "Furniture Assembly", Category: "Maintenance", BasePrice: 40.00, TenantBasePrice: 35.00, TenantPricePerKM: 1.00, Latitude: 30.0444, Longitude: 31.2360},
	}
}

// ---------------------------------------------------------------------------
// Haversine distance (simplified math-based proximity)
// ---------------------------------------------------------------------------

// haversineKm returns the great-circle distance in kilometres between two
// geographic coordinates using the Haversine formula.
func haversineKm(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadiusKm = 6371.0

	dLat := degreesToRadians(lat2 - lat1)
	dLon := degreesToRadians(lon2 - lon1)

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(degreesToRadians(lat1))*math.Cos(degreesToRadians(lat2))*
			math.Sin(dLon/2)*math.Sin(dLon/2)

	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadiusKm * c
}

func degreesToRadians(d float64) float64 {
	return d * math.Pi / 180
}
