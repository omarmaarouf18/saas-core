package geo

import (
	"container/list"
	"sync"
	"time"
)

type cacheEntry[V any] struct {
	key       string
	value     V
	expiresAt time.Time
}

// ttlCache is a bounded in-memory LRU cache with per-entry TTL expiration.
type ttlCache[V any] struct {
	mu         sync.Mutex
	maxEntries int
	ttl        time.Duration
	now        func() time.Time
	items      map[string]*list.Element
	order      *list.List
}

func newTTLCache[V any](maxEntries int, ttl time.Duration, now func() time.Time) *ttlCache[V] {
	if now == nil {
		now = func() time.Time { return time.Now().UTC() }
	}
	return &ttlCache[V]{
		maxEntries: maxEntries,
		ttl:        ttl,
		now:        now,
		items:      make(map[string]*list.Element),
		order:      list.New(),
	}
}

func (c *ttlCache[V]) Get(key string) (V, bool) {
	var zero V
	if c == nil || c.maxEntries <= 0 || c.ttl <= 0 {
		return zero, false
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	elem, ok := c.items[key]
	if !ok {
		return zero, false
	}
	entry := elem.Value.(*cacheEntry[V])
	if !c.now().Before(entry.expiresAt) {
		c.order.Remove(elem)
		delete(c.items, key)
		return zero, false
	}
	c.order.MoveToFront(elem)
	return entry.value, true
}

func (c *ttlCache[V]) Set(key string, value V) {
	if c == nil || c.maxEntries <= 0 || c.ttl <= 0 {
		return
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	expiresAt := c.now().Add(c.ttl)
	if elem, ok := c.items[key]; ok {
		entry := elem.Value.(*cacheEntry[V])
		entry.value = value
		entry.expiresAt = expiresAt
		c.order.MoveToFront(elem)
		return
	}

	for c.order.Len() >= c.maxEntries {
		back := c.order.Back()
		if back == nil {
			break
		}
		evicted := back.Value.(*cacheEntry[V])
		c.order.Remove(back)
		delete(c.items, evicted.key)
	}

	elem := c.order.PushFront(&cacheEntry[V]{
		key:       key,
		value:     value,
		expiresAt: expiresAt,
	})
	c.items[key] = elem
}

func (c *ttlCache[V]) Len() int {
	if c == nil {
		return 0
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.order.Len()
}
