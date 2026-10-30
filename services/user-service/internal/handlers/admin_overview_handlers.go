package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/project/shared/infra/handlerutil"
)

// AdminOverviewResponse is the aggregated JSON response for GET /admin/overview.
type AdminOverviewResponse struct {
	PendingKYBKYE               any            `json:"pending_kyb_kye"`
	PendingPaymentSubscriptions int64          `json:"pending_payment_subscriptions"`
	OpenTickets                 any            `json:"open_tickets"`
	AssignedTickets             any            `json:"assigned_tickets"`
	GPSDisputes                 int64          `json:"gps_disputes"`
	StuckCODJobs                int64          `json:"stuck_cod_jobs"`
	JobsToday                   map[string]int `json:"jobs_today"`
	NewAccountsToday            any            `json:"new_accounts_today"`
	NewAccounts7d               any            `json:"new_accounts_7d"`
	SuspendedAccounts           any            `json:"suspended_accounts"`
}

// AdminOverview handles GET /admin/overview & GET /users/admin/overview.
// Aggregates user-service data (pending subscriptions, GPS disputes, stuck COD jobs, jobs today)
// with auth-service and chat-service internal statistics using resilient timeouts and "unavailable" fallbacks.
func (u *UserService) AdminOverview(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeUnauthorized, "unauthorized", err)
		return
	}

	ctx := r.Context()

	// 1. Fetch user-service local metrics
	pendingSubs, gpsDisputes, stuckCODJobs, jobsToday, err := u.store.GetOverviewStats(ctx)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to get overview stats", err)
		return
	}

	// 2. Fetch auth-service and chat-service metrics concurrently with timeouts
	var (
		pendingKYC        any = "unavailable"
		newAccountsToday  any = "unavailable"
		newAccounts7d     any = "unavailable"
		suspendedAccounts any = "unavailable"
		openTickets       any = "unavailable"
		assignedTickets   any = "unavailable"
	)

	var wg sync.WaitGroup
	wg.Add(2)

	// Sub-task: auth-service stats
	go func() {
		defer wg.Done()
		authBase := u.authServiceURL
		if authBase == "" {
			authBase = "http://localhost:3002"
		}
		authURL := fmt.Sprintf("%s/auth/internal/overview-stats", strings.TrimSuffix(authBase, "/"))

		authCtx, authCancel := context.WithTimeout(ctx, 2*time.Second)
		defer authCancel()

		req, err := http.NewRequestWithContext(authCtx, http.MethodGet, authURL, nil)
		if err != nil {
			return
		}
		req.Header.Set("X-Internal-Token", u.internalServiceToken)

		var resp *http.Response
		if u.authClient != nil {
			resp, err = u.authClient.Do(req)
		} else {
			resp, err = http.DefaultClient.Do(req)
		}
		if err != nil {
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return
		}

		var stats struct {
			PendingKYBKYE     int64 `json:"pending_kyb_kye"`
			NewAccountsToday  int64 `json:"new_accounts_today"`
			NewAccounts7d     int64 `json:"new_accounts_7d"`
			SuspendedAccounts int64 `json:"suspended_accounts"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&stats); err == nil {
			pendingKYC = stats.PendingKYBKYE
			newAccountsToday = stats.NewAccountsToday
			newAccounts7d = stats.NewAccounts7d
			suspendedAccounts = stats.SuspendedAccounts
		}
	}()

	// Sub-task: chat-service stats
	go func() {
		defer wg.Done()
		chatBase := u.chatServiceURL
		if chatBase == "" {
			chatBase = "http://localhost:3003"
		}
		chatURL := fmt.Sprintf("%s/chat/internal/overview-stats", strings.TrimSuffix(chatBase, "/"))

		chatCtx, chatCancel := context.WithTimeout(ctx, 2*time.Second)
		defer chatCancel()

		req, err := http.NewRequestWithContext(chatCtx, http.MethodGet, chatURL, nil)
		if err != nil {
			return
		}
		req.Header.Set("X-Internal-Token", u.internalServiceToken)

		var resp *http.Response
		if u.chatClient != nil {
			resp, err = u.chatClient.Do(req)
		} else {
			resp, err = http.DefaultClient.Do(req)
		}
		if err != nil {
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return
		}

		var stats struct {
			OpenTickets     int64 `json:"open_tickets"`
			AssignedTickets int64 `json:"assigned_tickets"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&stats); err == nil {
			openTickets = stats.OpenTickets
			assignedTickets = stats.AssignedTickets
		}
	}()

	wg.Wait()

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_OVERVIEW_VIEWED", "user-service", reviewer.ID, "", "viewed admin overview statistics", handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, AdminOverviewResponse{
		PendingKYBKYE:               pendingKYC,
		PendingPaymentSubscriptions: pendingSubs,
		OpenTickets:                 openTickets,
		AssignedTickets:             assignedTickets,
		GPSDisputes:                 gpsDisputes,
		StuckCODJobs:                stuckCODJobs,
		JobsToday:                   jobsToday,
		NewAccountsToday:            newAccountsToday,
		NewAccounts7d:               newAccounts7d,
		SuspendedAccounts:           suspendedAccounts,
	})
}
