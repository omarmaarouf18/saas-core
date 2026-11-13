package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/project/chat-service/internal/config"
	"github.com/project/shared/infra/resilience"
)

func TestTokenCache_CapHolds(t *testing.T) {
	c := &Chat{
		tokenCache:    make(map[string]cachedToken),
		tokenCacheCap: 3,
	}

	now := time.Now()
	// Insert 5 entries (cap is 3)
	for i := 1; i <= 5; i++ {
		c.setCachedToken(fmt.Sprintf("user-%d", i), fmt.Sprintf("uname-%d", i), now.Add(time.Duration(i)*time.Minute))
	}

	c.tokenCacheMu.Lock()
	count := len(c.tokenCache)
	c.tokenCacheMu.Unlock()

	if count != 3 {
		t.Fatalf("expected tokenCache size to be capped at 3, got %d", count)
	}

	// The earliest-expiring entries (user-1, user-2) should have been evicted
	c.tokenCacheMu.Lock()
	_, found1 := c.tokenCache["user-1"]
	_, found2 := c.tokenCache["user-2"]
	_, found3 := c.tokenCache["user-3"]
	_, found4 := c.tokenCache["user-4"]
	_, found5 := c.tokenCache["user-5"]
	c.tokenCacheMu.Unlock()

	if found1 || found2 {
		t.Errorf("expected user-1 and user-2 to be evicted first")
	}
	if !found3 || !found4 || !found5 {
		t.Errorf("expected user-3, user-4, user-5 to remain in cache")
	}
}

func TestTokenCache_ExpiredEntriesEvicted(t *testing.T) {
	c := &Chat{
		tokenCache:    make(map[string]cachedToken),
		tokenCacheCap: 2, // Cap set to 2 so adding a 3rd entry triggers the cap-triggered sweep
	}

	now := time.Now()
	// Insert one expired entry and one active entry (len reaches cap 2)
	c.setCachedToken("expired-user", "expired-uname", now.Add(-10*time.Second))
	c.setCachedToken("active-user", "active-uname", now.Add(10*time.Second))

	// Inserting another entry when len == cap triggers sweep of expired entries
	c.setCachedToken("new-user", "new-uname", now.Add(10*time.Second))

	c.tokenCacheMu.Lock()
	_, expiredFound := c.tokenCache["expired-user"]
	_, activeFound := c.tokenCache["active-user"]
	_, newFound := c.tokenCache["new-user"]
	c.tokenCacheMu.Unlock()

	if expiredFound {
		t.Errorf("expected expired-user to be evicted from tokenCache when reaching cap")
	}
	if !activeFound || !newFound {
		t.Errorf("expected active-user and new-user to remain in tokenCache")
	}

	// Also verify lookup evicts expired entry directly
	c.tokenCacheMu.Lock()
	c.tokenCache["lookup-expired"] = cachedToken{
		expiry:   time.Now().Add(-5 * time.Second),
		username: "lookup-uname",
	}
	c.tokenCacheMu.Unlock()

	// Calling verifyToken on an expired entry will delete it on read
	c.authServiceURL = "http://127.0.0.1:0"
	c.authClient = resilience.NewClient(http.DefaultClient, "auth-test", 1, 100*time.Millisecond)
	valid, _, _ := c.verifyToken("lookup-expired")
	if valid {
		t.Errorf("expected verifyToken to return false for expired entry")
	}

	c.tokenCacheMu.Lock()
	_, stillPresent := c.tokenCache["lookup-expired"]
	c.tokenCacheMu.Unlock()
	if stillPresent {
		t.Errorf("expected lookup-expired to be deleted on read from tokenCache")
	}
}

func TestTokenCache_BelowCapDoesNotSweep(t *testing.T) {
	c := &Chat{
		tokenCache:    make(map[string]cachedToken),
		tokenCacheCap: 10,
	}

	now := time.Now()
	// Insert one already-expired entry
	c.setCachedToken("expired-user", "expired-uname", now.Add(-10*time.Second))

	// Insert entries below the cap (total entries = 4, cap = 10)
	c.setCachedToken("user-1", "uname-1", now.Add(1*time.Minute))
	c.setCachedToken("user-2", "uname-2", now.Add(1*time.Minute))
	c.setCachedToken("user-3", "uname-3", now.Add(1*time.Minute))

	c.tokenCacheMu.Lock()
	_, expiredFound := c.tokenCache["expired-user"]
	total := len(c.tokenCache)
	c.tokenCacheMu.Unlock()

	// Proves that inserts below cap do not sweep expired entries
	if !expiredFound {
		t.Fatalf("expected expired-user to remain in tokenCache when below cap, but was swept")
	}
	if total != 4 {
		t.Fatalf("expected 4 entries in tokenCache, got %d", total)
	}

	// Now fill to capLimit (10)
	for i := 4; i <= 9; i++ {
		c.setCachedToken(fmt.Sprintf("user-%d", i), fmt.Sprintf("uname-%d", i), now.Add(1*time.Minute))
	}
	// At this point len is 10 (expired-user + 9 active users). The next insert reaches/exceeds cap and triggers sweep:
	c.setCachedToken("user-10", "uname-10", now.Add(1*time.Minute))

	c.tokenCacheMu.Lock()
	_, expiredStillFound := c.tokenCache["expired-user"]
	newTotal := len(c.tokenCache)
	c.tokenCacheMu.Unlock()

	if expiredStillFound {
		t.Fatalf("expected expired-user to be swept once cap was reached")
	}
	if newTotal != 10 {
		t.Fatalf("expected exactly 10 entries after sweep and insert, got %d", newTotal)
	}
}

func TestTokenCache_CachedHitAvoidsHTTPCall(t *testing.T) {
	var httpHits int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&httpHits, 1)
		id := r.URL.Query().Get("id")
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"id":       id,
			"username": "user_" + id,
		})
	}))
	defer server.Close()

	cfg := &config.Config{
		AuthServiceURL:       server.URL,
		InternalServiceToken: "test-internal-token",
	}
	client := resilience.NewClient(http.DefaultClient, "auth-test", 2, 1*time.Second)
	c := &Chat{
		authServiceURL:       cfg.AuthServiceURL,
		internalServiceToken: cfg.InternalServiceToken,
		authClient:           client,
		tokenCache:           make(map[string]cachedToken),
		tokenCacheCap:        100,
	}

	// 1. First call -> misses cache, hits HTTP server
	valid, uname, err := c.verifyToken("test-user-1")
	if err != nil || !valid || uname != "user_test-user-1" {
		t.Fatalf("first verifyToken failed: valid=%v uname=%s err=%v", valid, uname, err)
	}
	if hits := atomic.LoadInt32(&httpHits); hits != 1 {
		t.Fatalf("expected 1 HTTP hit, got %d", hits)
	}

	// 2. Second call -> hits cache, avoids HTTP server
	valid, uname, err = c.verifyToken("test-user-1")
	if err != nil || !valid || uname != "user_test-user-1" {
		t.Fatalf("second verifyToken failed: valid=%v uname=%s err=%v", valid, uname, err)
	}
	if hits := atomic.LoadInt32(&httpHits); hits != 1 {
		t.Fatalf("expected HTTP hit count to stay 1 for cached hit, got %d", hits)
	}
}

func TestTokenCache_URLEscaping(t *testing.T) {
	var receivedRawQuery string
	var receivedIDParam string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedRawQuery = r.URL.RawQuery
		receivedIDParam = r.URL.Query().Get("id")
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"id":       receivedIDParam,
			"username": "escaped-user",
		})
	}))
	defer server.Close()

	client := resilience.NewClient(http.DefaultClient, "auth-test", 2, 1*time.Second)
	c := &Chat{
		authServiceURL:       server.URL,
		internalServiceToken: "test-internal-token",
		authClient:           client,
		tokenCache:           make(map[string]cachedToken),
		tokenCacheCap:        100,
	}

	// Special characters that must be escaped
	rawID := "user with spaces&param=injected/slash?query=1"
	valid, _, err := c.verifyToken(rawID)
	if err != nil || !valid {
		t.Fatalf("verifyToken with special chars failed: valid=%v err=%v", valid, err)
	}

	if receivedIDParam != rawID {
		t.Errorf("expected received query ID to be %q, got %q", rawID, receivedIDParam)
	}
	// Verify raw query has no unescaped spaces or query-splitting ampersands
	if receivedRawQuery == fmt.Sprintf("id=%s", rawID) {
		t.Errorf("raw query was not URL-escaped: %s", receivedRawQuery)
	}
}

func TestTokenCache_ConcurrentAccessRace(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.URL.Query().Get("id")
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"id":       id,
			"username": "user_" + id,
		})
	}))
	defer server.Close()

	client := resilience.NewClient(http.DefaultClient, "auth-test", 2, 1*time.Second)
	c := &Chat{
		authServiceURL:       server.URL,
		internalServiceToken: "test-internal-token",
		authClient:           client,
		tokenCache:           make(map[string]cachedToken),
		tokenCacheCap:        10, // Small cap to trigger constant eviction during concurrency
	}

	var wg sync.WaitGroup
	const goroutines = 20
	const iterations = 50

	for g := 0; g < goroutines; g++ {
		wg.Add(1)
		go func(gid int) {
			defer wg.Done()
			for i := 0; i < iterations; i++ {
				// Mix of shared IDs (hits) and unique IDs (evictions & misses)
				id := fmt.Sprintf("user-%d", (gid+i)%15)
				_, _, _ = c.verifyToken(id)
			}
		}(g)
	}

	wg.Wait()

	c.tokenCacheMu.Lock()
	size := len(c.tokenCache)
	c.tokenCacheMu.Unlock()

	if size > 10 {
		t.Errorf("expected final cache size <= 10, got %d", size)
	}
}
