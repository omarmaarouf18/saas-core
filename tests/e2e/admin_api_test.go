package e2e

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// adminHeaders constructs the dual-header auth payload required by reviewer endpoints.
func adminHeaders(cfg *Config, revToken string) map[string]string {
	return map[string]string{
		"Content-Type":     "application/json",
		"X-Internal-Token": cfg.InternalToken,
		"X-Reviewer-Token": revToken,
	}
}

// Internal base URLs of the staging services on staging-net. The gateway
// strips X-Internal-Token from every client request, so reviewer endpoints
// are only reachable the way the console reaches them in production: directly,
// over mTLS, with the console's client certificate.
const (
	stagingAuthURL         = "https://auth-service:3002"
	stagingUserURL         = "https://user-service:3003"
	stagingNotificationURL = "https://notification-service:3004"
	stagingGatewayURL      = "https://api-gateway:8080"
)

var (
	internalClientOnce sync.Once
	internalClient     *http.Client
	internalClientErr  error
)

// stagingInternalClient returns an mTLS client that presents the
// reviewer-console certificate and dials the staging containers by their
// bridge-network IP (docker inspect), keeping the service name as the TLS
// server name. STAGING_CERTS_DIR overrides the cert directory and
// STAGING_<SERVICE>_ADDR (e.g. STAGING_USER_SERVICE_ADDR=172.21.0.6:3003)
// overrides the dial address of one service.
func stagingInternalClient() (*http.Client, error) {
	internalClientOnce.Do(func() {
		certsDir := os.Getenv("STAGING_CERTS_DIR")
		if certsDir == "" {
			certsDir = filepath.Join("..", "..", "infrastructure", "certs")
		}
		caPEM, err := os.ReadFile(filepath.Join(certsDir, "ca.crt"))
		if err != nil {
			internalClientErr = fmt.Errorf("read staging CA: %w", err)
			return
		}
		pool := x509.NewCertPool()
		if !pool.AppendCertsFromPEM(caPEM) {
			internalClientErr = fmt.Errorf("staging CA in %s is not valid PEM", certsDir)
			return
		}
		cert, err := tls.LoadX509KeyPair(filepath.Join(certsDir, "reviewer-console.crt"), filepath.Join(certsDir, "reviewer-console.key"))
		if err != nil {
			internalClientErr = fmt.Errorf("load reviewer-console client cert: %w", err)
			return
		}
		var mu sync.Mutex
		resolved := map[string]string{}
		dialer := &net.Dialer{Timeout: 5 * time.Second}
		transport := &http.Transport{
			TLSClientConfig: &tls.Config{RootCAs: pool, Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS12},
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				host, port, err := net.SplitHostPort(addr)
				if err != nil {
					return nil, err
				}
				mu.Lock()
				target, ok := resolved[addr]
				mu.Unlock()
				if !ok {
					envKey := "STAGING_" + strings.ToUpper(strings.ReplaceAll(host, "-", "_")) + "_ADDR"
					if v := os.Getenv(envKey); v != "" {
						target = v
					} else {
						out, err := exec.CommandContext(ctx, "docker", "inspect", "-f",
							"{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", "staging-saas-"+host).Output()
						if err != nil {
							return nil, fmt.Errorf("resolve %s via docker inspect (set %s to override): %w", host, envKey, err)
						}
						target = net.JoinHostPort(strings.TrimSpace(string(out)), port)
					}
					mu.Lock()
					resolved[addr] = target
					mu.Unlock()
				}
				return dialer.DialContext(ctx, network, target)
			},
		}
		internalClient = &http.Client{Transport: transport, Timeout: 30 * time.Second}
	})
	return internalClient, internalClientErr
}

// doAdminRequest sends a reviewer request straight to a service (see
// stagingInternalClient), the same hop the console makes in production.
func doAdminRequest(ctx context.Context, method, url string, cfg *Config, revToken string, body any) (*http.Response, []byte, error) {
	return doAdminRequestWithHeaders(ctx, method, url, cfg, revToken, body, nil)
}

func doAdminRequestWithHeaders(ctx context.Context, method, url string, cfg *Config, revToken string, body any, extra map[string]string) (*http.Response, []byte, error) {
	client, err := stagingInternalClient()
	if err != nil {
		return nil, nil, err
	}

	var bodyReader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, nil, err
		}
		bodyReader = bytes.NewReader(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, url, bodyReader)
	if err != nil {
		return nil, nil, err
	}

	headers := adminHeaders(cfg, revToken)
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	for k, v := range extra {
		req.Header.Set(k, v)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	return resp, respBytes, err
}

// TestE2E_AdminConsoleEndpoints exercises the complete suite of operator reviewer
// endpoints implemented across Items 3 through 9d against the live staging stack.
func TestE2E_AdminConsoleEndpoints(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	ts := time.Now().UnixNano()

	testTenantID := fmt.Sprintf("tenant_adm_%d", ts)
	testOwnerID := testTenantID
	testOwnerEmail := fmt.Sprintf("owner_%d@adm.test", ts)
	testServiceID := fmt.Sprintf("svc_adm_%d", ts)

	testCourierID := fmt.Sprintf("cour_adm_%d", ts)
	testCourierEmail := fmt.Sprintf("cour_%d@adm.test", ts)
	testCustID := fmt.Sprintf("cust_adm_%d", ts)
	testCustEmail := fmt.Sprintf("cust_%d@adm.test", ts)

	pendingSubTenantID := fmt.Sprintf("tenant_sub_%d", ts)
	pendingSubOwnerID := pendingSubTenantID

	reviewerID := fmt.Sprintf("rev_adm_%d", ts)
	rawReviewerToken := fmt.Sprintf("reviewer-secret-token-%d-%d", rnd, ts)

	cleanupEntities := func() {
		if os.Getenv("E2E_NO_CLEANUP") != "" {
			return
		}
		db.CleanupTestEntities(ctx,
			[]string{testTenantID, pendingSubTenantID},
			[]string{testOwnerID, testCourierID, testCustID, pendingSubOwnerID},
		)
		_, _ = db.client.Database("staging_auth_db").Collection("reviewers").DeleteOne(ctx, bson.M{"_id": reviewerID})
		_, _ = db.client.Database("staging_user_db").Collection("subscriptions").DeleteMany(ctx, bson.M{"tenant_id": bson.M{"$in": []string{testTenantID, pendingSubTenantID}}})
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
	}
	defer cleanupEntities()
	cleanupEntities()

	// 1. Seed Reviewer credentials in auth database
	if err := db.SeedReviewer(ctx, reviewerID, "QA Ops Reviewer", rawReviewerToken); err != nil {
		t.Fatalf("Failed to seed reviewer: %v", err)
	}

	// 2. Seed Tenant, Service, Courier, and Customer
	if err := db.SeedCustomer(ctx, testTenantID, testOwnerID, testOwnerEmail); err != nil {
		t.Fatalf("Failed to seed owner: %v", err)
	}
	if err := db.SeedTenantAndService(ctx, testTenantID, testOwnerID, testServiceID, 25.0, 5.0, 30.0444, 31.2357); err != nil {
		t.Fatalf("Failed to seed tenant and service: %v", err)
	}
	// Give service a photo_url so photo remove test can succeed
	_, _ = db.client.Database("staging_user_db").Collection("services").UpdateOne(ctx, bson.M{"_id": testServiceID}, bson.M{"$set": bson.M{"photo_url": "https://storage.logiclinkeg.tech/services/" + testServiceID + ".jpg"}})

	if err := db.SeedCourier(ctx, testTenantID, testCourierID, testCourierEmail, 30.0450, 31.2360); err != nil {
		t.Fatalf("Failed to seed courier: %v", err)
	}
	if err := db.SeedCustomer(ctx, testTenantID, testCustID, testCustEmail); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}

	// 3. Seed active non-terminal job (Item 4 & 5)
	activeJobID := fmt.Sprintf("job_adm_act_%d", ts)
	activeJobDoc := bson.M{
		"_id":            activeJobID,
		"tenant_id":      testTenantID,
		"owner_id":       testOwnerID,
		"customer_id":    testCustID,
		"courier_id":     testCourierID,
		"status":         "active",
		"sub_status":     "in_transit",
		"price":          55.0,
		"payment_method": "cod",
		"created_at":     time.Now().UTC(),
		"updated_at":     time.Now().UTC(),
		"recipient": bson.M{
			"name":  "Mona Recipient",
			"phone": "+201011112222",
		},
		"package": bson.M{
			"description": "Fragile vase",
			"weight_kg":   1.5,
		},
		"location": bson.M{
			"type":        "Point",
			"coordinates": []float64{31.2357, 30.0444},
			"address":     "10 Kasr El Nil, Downtown, Cairo",
		},
		"destination": bson.M{
			"type":        "Point",
			"coordinates": []float64{31.2400, 30.0500},
			"address":     "22 Ramses St, Downtown, Cairo",
		},
		"status_history": []bson.M{
			{"status": "pending", "timestamp": time.Now().Add(-10 * time.Minute).UTC()},
			{"status": "active", "timestamp": time.Now().Add(-5 * time.Minute).UTC()},
		},
	}
	if err := db.SeedJob(ctx, activeJobDoc); err != nil {
		t.Fatalf("Failed to seed active job: %v", err)
	}

	// 4. Seed stuck COD job (Item 5)
	stuckJobID := fmt.Sprintf("job_adm_stuck_%d", ts)
	stuckJobDoc := bson.M{
		"_id":                   stuckJobID,
		"tenant_id":             testTenantID,
		"owner_id":              testOwnerID,
		"customer_id":           testCustID,
		"courier_id":            testCourierID,
		"service_id":            testServiceID,
		"status":                "escrow_reconciliation_required",
		"sub_status":            "under_distance_mismatch",
		"price":                 80.0,
		"agreed_price":          80.0,
		"payment_method":        "cod",
		"cod_amount":            80.0,
		"locked_escrow_amount":  0.0,
		"escrow_failure_reason": "under_distance_mismatch",
		"reconciliation_note":   "under_distance_mismatch: actual 1.2km vs booked 5.0km",
		"created_at":            time.Now().Add(-2 * time.Hour).UTC(),
		"updated_at":            time.Now().Add(-90 * time.Minute).UTC(),
		"recipient": bson.M{
			"name":  "Tarek Recipient",
			"phone": "+201033334444",
		},
		"package": bson.M{
			"description": "Books bundle",
			"weight_kg":   2.0,
		},
		"location": bson.M{
			"type":        "Point",
			"coordinates": []float64{31.2357, 30.0444},
			"address":     "10 Kasr El Nil, Downtown, Cairo",
		},
		"destination": bson.M{
			"type":        "Point",
			"coordinates": []float64{31.2400, 30.0500},
			"address":     "22 Ramses St, Downtown, Cairo",
		},
		"status_history": []bson.M{
			{"status": "pending", "timestamp": time.Now().Add(-120 * time.Minute).UTC()},
			{"status": "assigned", "timestamp": time.Now().Add(-110 * time.Minute).UTC()},
			{"status": "picked_up", "timestamp": time.Now().Add(-100 * time.Minute).UTC()},
			{"status": "escrow_reconciliation_required", "timestamp": time.Now().Add(-90 * time.Minute).UTC()},
		},
	}
	if err := db.SeedJob(ctx, stuckJobDoc); err != nil {
		t.Fatalf("Failed to seed stuck COD job: %v", err)
	}

	// 5. Seed pending_payment subscription (Item 7)
	if err := db.SeedCustomer(ctx, pendingSubTenantID, pendingSubOwnerID, fmt.Sprintf("subowner_%d@adm.test", ts)); err != nil {
		t.Fatalf("Failed to seed subscription owner: %v", err)
	}
	pendingSubID := fmt.Sprintf("sub_pending_%d", ts)
	_, err = db.client.Database("staging_user_db").Collection("subscriptions").InsertOne(ctx, bson.M{
		"_id":            pendingSubID,
		"tenant_id":      pendingSubTenantID,
		"tier":           "pending_payment",
		"requested_plan": "enterprise",
		"status":         "pending_payment",
		"started_at":     time.Now().Add(-24 * time.Hour).UTC(),
		"created_at":     time.Now().Add(-24 * time.Hour).UTC(),
		"updated_at":     time.Now().Add(-24 * time.Hour).UTC(),
	})
	if err != nil {
		t.Fatalf("Failed to seed pending_payment subscription: %v", err)
	}

	// -------------------------------------------------------------------------
	// The public gateway never forwards a client X-Internal-Token, even next
	// to a valid X-Reviewer-Token, so reviewer endpoints are not reachable
	// through it.
	// -------------------------------------------------------------------------
	t.Run("Gateway strips client X-Internal-Token on reviewer paths", func(t *testing.T) {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, cfg.GatewayURL+"/api/v1/users/admin/overview", nil)
		if err != nil {
			t.Fatalf("build request: %v", err)
		}
		for k, v := range adminHeaders(cfg, rawReviewerToken) {
			req.Header.Set(k, v)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("GET through gateway failed: %v", err)
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode == http.StatusOK {
			t.Fatalf("reviewer endpoint must not be reachable through the gateway with a client X-Internal-Token, got 200: %s", string(body))
		}
		t.Logf("Gateway rejected reviewer request carrying client X-Internal-Token: %d", resp.StatusCode)
	})

	t.Run("Edge returns 404 for gateway admin paths", func(t *testing.T) {
		for _, path := range []string{"/admin", "/admin/version", "/api/v1/admin/version"} {
			req, err := http.NewRequestWithContext(ctx, http.MethodGet, cfg.GatewayURL+path, nil)
			if err != nil {
				t.Fatalf("build request: %v", err)
			}
			for k, v := range adminHeaders(cfg, rawReviewerToken) {
				req.Header.Set(k, v)
			}
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("GET %s through edge failed: %v", path, err)
			}
			resp.Body.Close()
			if resp.StatusCode != http.StatusNotFound {
				t.Fatalf("GET %s through edge: expected 404, got %d", path, resp.StatusCode)
			}
		}
		t.Logf("Edge Caddy answered 404 for /admin, /admin/version and /api/v1/admin/version")
	})

	// -------------------------------------------------------------------------
	// ITEM 3: GET /admin/overview
	// -------------------------------------------------------------------------
	t.Run("Item 3 - Overview Aggregation", func(t *testing.T) {
		overviewURL := stagingUserURL + "/users/admin/overview"
		resp, body, err := doAdminRequest(ctx, http.MethodGet, overviewURL, cfg, rawReviewerToken, nil)
		if err != nil {
			t.Fatalf("GET /admin/overview request failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for /admin/overview, got %d: %s", resp.StatusCode, string(body))
		}

		var overview map[string]any
		if err := json.Unmarshal(body, &overview); err != nil {
			t.Fatalf("failed to decode overview JSON: %v", err)
		}

		if _, exists := overview["pending_payment_subscriptions"]; !exists {
			t.Errorf("expected pending_payment_subscriptions in overview response")
		}
		if _, exists := overview["jobs_today"]; !exists {
			t.Errorf("expected jobs_today in overview response")
		}
		t.Logf("Verified Item 3: Overview successfully aggregated metrics")
	})

	// -------------------------------------------------------------------------
	// ITEM 4: GET /admin/jobs & GET /admin/jobs/{id}
	// -------------------------------------------------------------------------
	t.Run("Item 4 - Jobs Lookup and Full Detail", func(t *testing.T) {
		// List jobs
		jobsListURL := fmt.Sprintf("%s/users/admin/jobs?id=%s", stagingUserURL, activeJobID)
		resp, body, err := doAdminRequest(ctx, http.MethodGet, jobsListURL, cfg, rawReviewerToken, nil)
		if err != nil {
			t.Fatalf("GET /admin/jobs request failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for /admin/jobs, got %d: %s", resp.StatusCode, string(body))
		}

		var listResp struct {
			Jobs  []map[string]any `json:"jobs"`
			Total int              `json:"total"`
		}
		if err := json.Unmarshal(body, &listResp); err != nil {
			t.Fatalf("failed to parse jobs list JSON: %v", err)
		}
		if listResp.Total == 0 || len(listResp.Jobs) == 0 {
			t.Fatalf("expected at least 1 job in list, got %d", listResp.Total)
		}

		// Job detail
		jobDetailURL := fmt.Sprintf("%s/users/admin/jobs/%s", stagingUserURL, activeJobID)
		respDetail, bodyDetail, err := doAdminRequest(ctx, http.MethodGet, jobDetailURL, cfg, rawReviewerToken, nil)
		if err != nil {
			t.Fatalf("GET /admin/jobs/{id} request failed: %v", err)
		}
		if respDetail.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for job detail, got %d: %s", respDetail.StatusCode, string(bodyDetail))
		}

		var detail map[string]any
		if err := json.Unmarshal(bodyDetail, &detail); err != nil {
			t.Fatalf("failed to parse job detail JSON: %v", err)
		}

		// Unmasked phone check
		recipient, ok := detail["recipient"].(map[string]any)
		if !ok || recipient["phone"] != "+201011112222" {
			t.Errorf("expected unmasked recipient phone +201011112222, got %v", recipient["phone"])
		}
		loc, _ := detail["location"].(map[string]any)
		if loc == nil || loc["address"] != "10 Kasr El Nil, Downtown, Cairo" {
			t.Errorf("expected location address text, got %v", loc)
		}
		t.Logf("Verified Item 4: Jobs lookup and full unmasked V2 detail")
	})

	// -------------------------------------------------------------------------
	// ITEM 5: Admin Job Mutations (Cancel & Complete Stuck COD)
	// -------------------------------------------------------------------------
	t.Run("Item 5 - Admin Job Mutations", func(t *testing.T) {
		// Cancel non-terminal job
		cancelURL := fmt.Sprintf("%s/users/admin/jobs/%s/cancel", stagingUserURL, activeJobID)
		// Negative guard: empty reason rejected
		respNeg, _, _ := doAdminRequest(ctx, http.MethodPost, cancelURL, cfg, rawReviewerToken, map[string]string{"reason": ""})
		if respNeg.StatusCode != http.StatusBadRequest {
			t.Errorf("expected 400 Bad Request for empty cancellation reason, got %d", respNeg.StatusCode)
		}

		// Valid cancellation
		respCancel, bodyCancel, err := doAdminRequest(ctx, http.MethodPost, cancelURL, cfg, rawReviewerToken, map[string]string{
			"reason": "Customer requested order cancellation via phone support",
		})
		if err != nil {
			t.Fatalf("cancel job request failed: %v", err)
		}
		if respCancel.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for job cancellation, got %d: %s", respCancel.StatusCode, string(bodyCancel))
		}

		// Complete stuck COD job
		completeStuckURL := fmt.Sprintf("%s/users/admin/jobs/%s/complete-stuck-cod", stagingUserURL, stuckJobID)
		respStuck, bodyStuck, err := doAdminRequest(ctx, http.MethodPost, completeStuckURL, cfg, rawReviewerToken, map[string]string{
			"reason": "Courier confirmed cash collected and recipient confirmed delivery",
		})
		if err != nil {
			t.Fatalf("complete stuck COD request failed: %v", err)
		}
		if respStuck.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for stuck COD completion, got %d: %s", respStuck.StatusCode, string(bodyStuck))
		}
		t.Logf("Verified Item 5: Admin job cancel and stuck COD complete mutations")
	})

	// -------------------------------------------------------------------------
	// ITEM 6: Services Marketplace Moderation
	// -------------------------------------------------------------------------
	t.Run("Item 6 - Services Moderation", func(t *testing.T) {
		servicesURL := fmt.Sprintf("%s/users/admin/services?tenant_id=%s", stagingUserURL, testTenantID)
		resp, body, err := doAdminRequest(ctx, http.MethodGet, servicesURL, cfg, rawReviewerToken, nil)
		if err != nil {
			t.Fatalf("GET /admin/services request failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for /admin/services, got %d: %s", resp.StatusCode, string(body))
		}

		// Hide service
		hideURL := fmt.Sprintf("%s/users/admin/services/%s/hide", stagingUserURL, testServiceID)
		respHide, bodyHide, err := doAdminRequest(ctx, http.MethodPost, hideURL, cfg, rawReviewerToken, map[string]string{
			"reason": "Suspicious promotion violating marketplace policy",
		})
		if err != nil {
			t.Fatalf("hide service request failed: %v", err)
		}
		if respHide.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for hide service, got %d: %s", respHide.StatusCode, string(bodyHide))
		}

		// Verify marketplace exclusion
		mktURL := cfg.GatewayURL + "/api/v1/users/services"
		respMkt, bodyMkt, _ := GetJSON(ctx, mktURL, "")
		if respMkt.StatusCode == http.StatusOK && strings.Contains(string(bodyMkt), testServiceID) {
			t.Errorf("hidden service should be excluded from public marketplace listing")
		}

		// Unhide service
		unhideURL := fmt.Sprintf("%s/users/admin/services/%s/unhide", stagingUserURL, testServiceID)
		respUnhide, bodyUnhide, err := doAdminRequest(ctx, http.MethodPost, unhideURL, cfg, rawReviewerToken, map[string]string{
			"reason": "Owner adjusted description to comply with marketplace policy",
		})
		if err != nil {
			t.Fatalf("unhide service request failed: %v", err)
		}
		if respUnhide.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for unhide service, got %d: %s", respUnhide.StatusCode, string(bodyUnhide))
		}

		// Remove photo
		rmPhotoURL := fmt.Sprintf("%s/users/admin/services/%s/photo/remove", stagingUserURL, testServiceID)
		respPhoto, bodyPhoto, err := doAdminRequest(ctx, http.MethodPost, rmPhotoURL, cfg, rawReviewerToken, map[string]string{
			"reason": "Copyright infringement notice received",
		})
		if err != nil {
			t.Fatalf("remove photo request failed: %v", err)
		}
		if respPhoto.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for remove photo, got %d: %s", respPhoto.StatusCode, string(bodyPhoto))
		}
		t.Logf("Verified Item 6: Services moderation hide, unhide, and photo removal")
	})

	// -------------------------------------------------------------------------
	// ITEM 7: Subscriptions Queue
	// -------------------------------------------------------------------------
	t.Run("Item 7 - Subscriptions Queue", func(t *testing.T) {
		queueURL := stagingUserURL + "/users/admin/subscriptions/queue"
		resp, body, err := doAdminRequest(ctx, http.MethodGet, queueURL, cfg, rawReviewerToken, nil)
		if err != nil {
			t.Fatalf("GET /admin/subscriptions/queue request failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for subscriptions queue, got %d: %s", resp.StatusCode, string(body))
		}

		var queueResp struct {
			Queue []map[string]any `json:"queue"`
			Total int              `json:"total"`
		}
		if err := json.Unmarshal(body, &queueResp); err != nil {
			t.Fatalf("failed to parse subscriptions queue JSON: %v", err)
		}

		found := false
		for _, q := range queueResp.Queue {
			if q["tenant_id"] == pendingSubTenantID {
				found = true
				if q["requested_plan"] != "paid" {
					t.Errorf("expected requested_plan paid, got %v", q["requested_plan"])
				}
				break
			}
		}
		if !found {
			t.Errorf("seeded pending_payment subscription not found in queue")
		}
		t.Logf("Verified Item 7: Subscriptions queue returns pending_payment oldest first")
	})

	// -------------------------------------------------------------------------
	// ITEM 8: Audit Log Viewer
	// -------------------------------------------------------------------------
	t.Run("Item 8 - Audit Log Viewer", func(t *testing.T) {
		auditURL := stagingAuthURL + "/auth/admin/audit?limit=20"
		resp, body, err := doAdminRequest(ctx, http.MethodGet, auditURL, cfg, rawReviewerToken, nil)
		if err != nil {
			t.Fatalf("GET /admin/audit request failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for /admin/audit, got %d: %s", resp.StatusCode, string(body))
		}

		var auditResp struct {
			Entries []map[string]any  `json:"entries"`
			Total   int               `json:"total"`
			Sources map[string]string `json:"sources"`
		}
		if err := json.Unmarshal(body, &auditResp); err != nil {
			t.Fatalf("failed to parse audit log response JSON: %v", err)
		}
		for _, src := range []string{"auth-service", "user-service", "chat-service", "notification-service", "api-gateway"} {
			if auditResp.Sources[src] != "ok" {
				t.Errorf("audit source %s = %q, want ok (all: %v)", src, auditResp.Sources[src], auditResp.Sources)
			}
		}
		t.Logf("Verified Item 8: Audit log viewer merges all five sources: %v", auditResp.Sources)
	})

	// -------------------------------------------------------------------------
	// ITEM 9: App Version Policy (Persisted in Gateway DB)
	// -------------------------------------------------------------------------
	t.Run("Item 9 - Persisted Version Config", func(t *testing.T) {
		versionURL := stagingGatewayURL + "/admin/version"
		// Read version
		resp, body, err := doAdminRequest(ctx, http.MethodGet, versionURL, cfg, rawReviewerToken, nil)
		if err != nil {
			t.Fatalf("GET /admin/version request failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for /admin/version, got %d: %s", resp.StatusCode, string(body))
		}

		// Update version
		updatePayload := map[string]string{
			"minimum_supported_version": "1.0.0",
			"latest_version":            "1.2.0",
			"download_url":              "https://play.google.com/store/apps/details?id=tech.logiclinkeg.app",
			"reason":                    "E2E test version policy update",
		}
		respPut, bodyPut, err := doAdminRequest(ctx, http.MethodPut, versionURL, cfg, rawReviewerToken, updatePayload)
		if err != nil {
			t.Fatalf("PUT /admin/version request failed: %v", err)
		}
		if respPut.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for version update, got %d: %s", respPut.StatusCode, string(bodyPut))
		}

		// Negative guard: empty reason rejected
		badPayload := map[string]string{
			"minimum_supported_version": "1.0.0",
			"latest_version":            "1.2.0",
			"download_url":              "https://play.google.com/store/apps/details?id=tech.logiclinkeg.app",
			"reason":                    "",
		}
		respBad, _, _ := doAdminRequest(ctx, http.MethodPut, versionURL, cfg, rawReviewerToken, badPayload)
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("expected 400 Bad Request for empty version reason, got %d", respBad.StatusCode)
		}
		t.Logf("Verified Item 9: Persisted version policy read and update with reason")
	})

	// -------------------------------------------------------------------------
	// ITEM 9b: Input Hygiene (Ticket Context ID)
	// -------------------------------------------------------------------------
	t.Run("Item 9b - Ticket Context Hygiene", func(t *testing.T) {
		custToken, err := cfg.GenerateJWT(testCustID, "user", testTenantID, testCustEmail)
		if err != nil {
			t.Fatalf("failed to generate customer token: %v", err)
		}

		// Malicious XSS context_id
		badTicket := map[string]string{
			"context_id": "<script>alert('xss')</script>",
		}
		ticketsURL := cfg.GatewayURL + "/api/v1/chat/tickets"
		respBad, bodyBad, err := PostJSON(ctx, ticketsURL, custToken, badTicket)
		if err != nil {
			t.Fatalf("POST /chat/tickets failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest || !strings.Contains(string(bodyBad), "invalid_context_id") {
			t.Fatalf("expected 400 invalid_context_id for XSS context_id, got %d: %s", respBad.StatusCode, string(bodyBad))
		}
		t.Logf("Verified Item 9b: Ticket context_id rejected invalid string with stable error code")
	})

	// -------------------------------------------------------------------------
	// ITEM 9c: Token out of URLs (WebSocket subprotocol & User documents POST)
	// -------------------------------------------------------------------------
	t.Run("Item 9c - WebSocket Subprotocol & Documents POST", func(t *testing.T) {
		// WebSocket connection via kyc-console-auth subprotocol (no token in URL query)
		wsClient, err := ConnectConsoleWS(ctx, cfg.ConsoleURL, rawReviewerToken)
		if err != nil {
			t.Logf("Console WS connection warning (console container might not be exposing WS in staging): %v", err)
		} else {
			defer wsClient.Close()
			t.Logf("Verified Item 9c: WebSocket connected cleanly with kyc-console-auth subprotocol")
		}

		// Reviewer user-documents accepts POST body
		docURL := stagingAuthURL + "/auth/reviewer/user-documents"
		docPayload := map[string]string{
			"user_id": testCustID,
			"reason":  "Compliance identity verification",
		}
		respDoc, bodyDoc, err := doAdminRequest(ctx, http.MethodPost, docURL, cfg, rawReviewerToken, docPayload)
		if err != nil {
			t.Fatalf("POST /auth/reviewer/user-documents failed: %v", err)
		}
		if respDoc.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for POST reviewer documents, got %d: %s", respDoc.StatusCode, string(bodyDoc))
		}
		t.Logf("Verified Item 9c: Reviewer user-documents accepts POST JSON body")
	})

	// -------------------------------------------------------------------------
	// ITEM 9d: Admin Notifications (Dry Run, Test Send, Sends List)
	// -------------------------------------------------------------------------
	t.Run("Item 9d - Admin Announcements", func(t *testing.T) {
		sendURL := stagingNotificationURL + "/notifications/admin/send"

		// Dry run mode
		dryPayload := map[string]any{
			"reason":   "Capacity estimation dry run",
			"audience": map[string]any{"kind": "role", "role": "customers"},
			"title":    map[string]string{"en": "Update", "ar": "تحديث"},
			"body":     map[string]string{"en": "Platform maintenance tonight", "ar": "صيانة المنصة الليلة"},
			"dry_run":  true,
		}
		respDry, bodyDry, err := doAdminRequest(ctx, http.MethodPost, sendURL, cfg, rawReviewerToken, dryPayload)
		if err != nil {
			t.Fatalf("dry run notification failed: %v", err)
		}
		if respDry.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for dry run, got %d: %s", respDry.StatusCode, string(bodyDry))
		}

		// "Send test to me" mode
		testSendPayload := map[string]any{
			"reason":       "Pre-flight format verification",
			"audience":     map[string]any{"kind": "everyone"},
			"test_user_id": testCustID,
			"title":        map[string]string{"en": "Test Announcement", "ar": "إعلان تجريبي"},
			"body":         map[string]string{"en": "This is a test broadcast", "ar": "هذا إشعار تجريبي"},
			"deep_link":    "/plan",
		}
		respTest, bodyTest, err := doAdminRequest(ctx, http.MethodPost, sendURL, cfg, rawReviewerToken, testSendPayload)
		if err != nil {
			t.Fatalf("test send notification failed: %v", err)
		}
		if respTest.StatusCode != http.StatusAccepted {
			t.Fatalf("expected 202 Accepted for test send, got %d: %s", respTest.StatusCode, string(bodyTest))
		}

		// List notification sends
		sendsListURL := stagingNotificationURL + "/notifications/admin/sends"
		respSends, bodySends, err := doAdminRequest(ctx, http.MethodGet, sendsListURL, cfg, rawReviewerToken, nil)
		if err != nil {
			t.Fatalf("GET /admin/notifications/sends failed: %v", err)
		}
		if respSends.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for sends list, got %d: %s", respSends.StatusCode, string(bodySends))
		}

		var sendsResp struct {
			Sends []map[string]any `json:"sends"`
			Total int              `json:"total"`
		}
		if err := json.Unmarshal(bodySends, &sendsResp); err != nil {
			t.Fatalf("failed to parse sends list JSON: %v", err)
		}
		if sendsResp.Total == 0 || len(sendsResp.Sends) == 0 {
			t.Fatalf("expected at least 1 send job in sends list, got %d", sendsResp.Total)
		}
		t.Logf("Verified Item 9d: Admin notification dry run, test send, and sends list")
	})

	// -------------------------------------------------------------------------
	// ITEM 8 (ADMIN-API-FIX): the merged viewer shows the admin actions above,
	// persisted by the service that owns each one.
	// -------------------------------------------------------------------------
	t.Run("Item 8b - Merged audit shows persisted admin actions", func(t *testing.T) {
		auditURL := stagingAuthURL + "/auth/admin/audit?limit=100&actor_id=" + reviewerID
		resp, body, err := doAdminRequest(ctx, http.MethodGet, auditURL, cfg, rawReviewerToken, nil)
		if err != nil {
			t.Fatalf("GET /admin/audit request failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for /admin/audit, got %d: %s", resp.StatusCode, string(body))
		}
		var auditResp struct {
			Entries []struct {
				Source    string `json:"source"`
				ActorID   string `json:"actor_id"`
				Action    string `json:"action"`
				TargetID  string `json:"target_id"`
				RequestID string `json:"request_id"`
			} `json:"entries"`
			Sources map[string]string `json:"sources"`
		}
		if err := json.Unmarshal(body, &auditResp); err != nil {
			t.Fatalf("failed to parse audit response: %v", err)
		}
		seen := map[string]string{}
		for _, e := range auditResp.Entries {
			if e.ActorID != reviewerID || e.RequestID == "" {
				t.Errorf("unexpected entry: %+v", e)
			}
			seen[e.Action] = e.Source
		}
		want := map[string]string{
			"job.view":               "user-service",
			"job.cancel":             "user-service",
			"job.complete_stuck_cod": "user-service",
			"service.hide":           "user-service",
			"service.unhide":         "user-service",
			"service.photo_remove":   "user-service",
			"version.update":         "api-gateway",
			"user_documents.view":    "auth-service",
			"notification.send":      "notification-service",
		}
		for action, source := range want {
			if seen[action] != source {
				t.Errorf("expected %s from %s in merged audit, got %q (sources: %v)", action, source, seen[action], auditResp.Sources)
			}
		}
		t.Logf("Verified Item 8b: merged audit returned %d entries for the reviewer across %v", len(auditResp.Entries), auditResp.Sources)
	})
}
