package handlers

import (
	"encoding/json"
	"fmt"
	"html"
	"net/http"
	"strings"
	"time"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/user-service/internal/models"
	"go.mongodb.org/mongo-driver/mongo"
)

// ---------------------------------------------------------------------------
// POST /users/jobs/rate
// ---------------------------------------------------------------------------

func (u *UserService) RateJob(w http.ResponseWriter, r *http.Request) {
	ip := handlerutil.GetIP(r)
	if limited, remaining := u.limiter.CheckAndRecord("rate_job:" + ip); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	var req struct {
		JobID          string `json:"job_id"`
		RatedBy        string `json:"rated_by"`
		RatedByToken   string `json:"rated_by_token"`
		RatedUser      string `json:"rated_user"`
		RatedUserToken string `json:"rated_user_token"`
		Stars          int    `json:"stars"`
		Comment        string `json:"comment"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if req.RatedByToken != "" {
		req.RatedBy = req.RatedByToken
	}
	if req.RatedUserToken != "" {
		req.RatedUser = req.RatedUserToken
	}

	if req.Stars < 1 || req.Stars > 5 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "stars must be between 1 and 5"})
		return
	}

	if len(req.Comment) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "comment exceeds maximum length of 1000 characters"})
		return
	}
	req.Comment = strings.TrimSpace(html.EscapeString(req.Comment))

	resolvedRatedBy, err := resolveTokenWithRole(req.RatedBy, "owner", "employee", "user", "customer")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid rated_by token: " + err.Error()})
		return
	}
	req.RatedBy = resolvedRatedBy

	resolvedRatedUser, err := resolveTokenWithRole(req.RatedUser, "owner", "employee", "user", "customer")
	if err == nil {
		req.RatedUser = resolvedRatedUser
	} // Fallback: if token resolution fails, treat req.RatedUser as the raw user ID directly

	ctx := r.Context()
	job := u.store.GetJob(ctx, req.JobID)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	isOwnerRating := req.RatedBy == job.OwnerID && req.RatedUser == job.EmployeeID
	isEmployeeRating := req.RatedBy == job.EmployeeID && req.RatedUser == job.OwnerID

	if !isOwnerRating && !isEmployeeRating {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "not authorized to rate this job/user"})
		return
	}

	if job.Status != models.JobStatusCompleted {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cannot rate a job that is not completed"})
		return
	}

	rating := &models.Rating{
		ID:        "rate-" + generateID(),
		JobID:     req.JobID,
		RatedBy:   req.RatedBy,
		RatedUser: req.RatedUser,
		Stars:     req.Stars,
		Comment:   req.Comment,
		CreatedAt: time.Now().UTC(),
	}

	if err := u.store.CreateRating(ctx, rating); err != nil {
		if mongo.IsDuplicateKeyError(err) || strings.Contains(err.Error(), "11000") || strings.Contains(err.Error(), "duplicate key") {
			writeJSON(w, http.StatusConflict, map[string]string{
				"error":   "conflict",
				"message": "you have already rated this job",
			})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusCreated, rating)
}

// ---------------------------------------------------------------------------
// GET /users/ratings?user_id=xxx
// ---------------------------------------------------------------------------

func (u *UserService) GetRatings(w http.ResponseWriter, r *http.Request) {
	ip := handlerutil.GetIP(r)
	if limited, remaining := u.ratingsLimiter.CheckAndRecord("get_ratings:" + ip); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	// Authenticate requester
	requesterToken := r.Header.Get("Authorization")
	if strings.HasPrefix(requesterToken, "Bearer ") {
		requesterToken = strings.TrimPrefix(requesterToken, "Bearer ")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_id")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("user_token")
	}
	if requesterToken == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "requester authorization token required"})
		return
	}

	_, err := resolveTokenWithRole(requesterToken, "owner", "employee", "user", "customer")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	// Target user ID to query (can be raw ID or JWT token)
	targetUserID := r.URL.Query().Get("user_id")
	if targetUserID == "" {
		targetUserID = r.URL.Query().Get("user_token")
	}
	if targetUserID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "user_id required"})
		return
	}

	resolvedTarget, err := resolveTokenWithRole(targetUserID, "owner", "employee", "user", "customer")
	if err == nil {
		targetUserID = resolvedTarget
	} else {
		// Raw-ID fall-through is restricted (QA audit Q24): business
		// reputation (owner/employee targets) stays publicly queryable for
		// the ADR-0014 directory/marketplace; customer rating histories are
		// private blind-feedback data and require the customer's own token.
		role, roleErr := u.fetchUserRole(r.Context(), targetUserID)
		if roleErr != nil || (role != "owner" && role != "employee") {
			writeJSON(w, http.StatusForbidden, map[string]string{
				"error": "access denied: customer rating histories require the customer's own token",
			})
			return
		}
	}

	// Server-side pagination: default page of 50, hard cap of 200.
	limit := int64(parseIntDefault(r.URL.Query().Get("limit"), 50))
	offset := int64(parseIntDefault(r.URL.Query().Get("offset"), 0))
	ratings, err := u.store.GetRatingsForUser(r.Context(), targetUserID, limit, offset)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	totalStars := 0
	for _, r := range ratings {
		totalStars += r.Stars
	}

	avg := 0.0
	if len(ratings) > 0 {
		avg = float64(totalStars) / float64(len(ratings))
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"user_id":        targetUserID,
		"ratings":        ratings,
		"average_rating": avg,
		"count":          len(ratings),
	})
}
