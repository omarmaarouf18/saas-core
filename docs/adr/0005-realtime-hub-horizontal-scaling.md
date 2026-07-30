# ADR-0005: Realtime Hub Horizontal Scaling via Redis Pub/Sub

- **Status**: Accepted
- **Date**: 2026-07-26
- **Related Commit SHA**: ``09263f46220a89da4b93e4805283944c3f0d954a``
- **Related audit finding**: In-memory single-instance WebSocket (`chat-service`) and SSE (`notification-service`) connection hubs causing silent message/notification loss when scaled across 2 or more replicas.

## Context
Currently, both `chat-service` (`services/chat-service/internal/chat/hub.go`) and `notification-service` (`services/notification-service/internal/hub/hub.go`) maintain active client connections in plain in-process Go maps (`clients map[*Client]bool`, `channels map[string]map[*Client]bool`, and `clients map[*SSEClient]bool`).
When running multiple service replicas behind `api-gateway`, a client connected to Instance A will not receive messages or notifications dispatched on Instance B:
1. In `chat-service`, if User A connects to Instance 1 and User B connects to Instance 2 for channel `job:123`, messages sent by User A land on Instance 1's `h.Broadcast` channel and are only delivered to clients on Instance 1. User B on Instance 2 misses them.
2. In `notification-service`, internal API calls (`POST /notifications/send`, `POST /notifications/broadcast/job-alert`) land on a single replica routed by `api-gateway`. That replica delivers alerts only to its own locally connected SSE clients; clients connected to other replicas receive nothing.

All other core microservices (`api-gateway`, `auth-service`, `user-service`) are already horizontally scale-safe via Redis-backed rate limiting/idempotency, stateless JWT authentication, and pooled database connections.

> [!NOTE]
> **Correction Note (2026-07-27)**: The statement above asserting that `user-service` was fully horizontally scale-safe at the time this ADR was written was partially inaccurate. While `TrackJob`'s idempotency key handling was indeed Redis-backed, `UpdateJobLocation`'s per-job location update throttle state (`locationInFlight` and `locationLastUpdate`) relied on in-process Go maps (`map[string]bool` / `map[string]time.Time`). This in-memory throttle state has been migrated to Redis-backed atomic key evaluation with TTLs in `user-service` (`services/user-service/internal/handlers/handlers.go`, commit `24b10339f37342e4280bdc9d32099bb44e5a7fba`).

## Decision
We decided to implement horizontal scale safety for both real-time hubs using **Redis Pub/Sub** via `github.com/redis/go-redis/v9` (reusing `shared/infra/ratelimit.NewRedisClient`).

### 1. `notification-service` Design (One-Way Server-Sent Events)
- **Client Identity Channel Subscription**: On SSE connection open (`/notifications/stream`), the instance registers the client locally (unchanged) AND subscribes to a Redis Pub/Sub channel scoped to the client's target identity/tenant (e.g. `notify:user:<user_id>` and `notify:tenant:<tenant_id>`), plus a global broadcast channel (`notify:broadcast:global`).
- **Publishing & Fan-Out**: When `/notifications/send` or `/notifications/broadcast/job-alert` is called on any instance, the handler serializes the `Notification` payload to JSON and executes `rdb.Publish(ctx, channel, payload)` to the target Redis Pub/Sub channel(s).
- **Remote Forwarding**: Every `notification-service` replica listening on the Redis channel receives the published notification via its subscriber loop, matches locally connected SSE clients (`c.TenantID`, `c.Role`, `c.ID`), and forwards the SSE payload directly to matching local client `Send` channels.

### 2. `chat-service` Design (Bidirectional Channel-Scoped WebSockets)
- **Dynamic Channel Subscription (Zero-Interest Optimization)**: To avoid unnecessary cross-instance Redis traffic, a `chat-service` instance dynamically subscribes to a Redis channel `chat:channel:<channel_name>` only when the first local client joins that channel (`Subscribe`), and unsubscribes from Redis when the last local client leaves (`Unsubscribe` / disconnect).
- **Publishing & Fan-Out**: When a WebSocket message or internal location update (`POST /chat/internal/broadcast-location`) arrives at any instance, `Hub.Broadcast` publishes the JSON `Message` to `chat:channel:<channel_name>` in Redis.
- **Preserved In-Memory Semantics**: The Redis subscriber handler receives the message and fans it out strictly to matching locally-connected clients using `sendToClient(client, msg)`. Internal hub semantics (`Register`, `Unregister`, `Subscribe`, `Unsubscribe`, `ClientCount`, `ChannelCount`) and existing single-instance unit tests remain 100% unchanged internally.

### 3. Failure Mode & Degraded Behavior (Product/Ops Decision)
- **Redis Unavailability & Interruption**:
  - Unlike financial rate limiting (which fails-closed to block brute-force traffic), real-time hubs prioritize **high availability and local delivery continuity**.
  - If Redis is unconfigured (`REDIS_ADDR` empty) or briefly unreachable during runtime, hubs log a critical warning `[REDIS-PUBSUB-WARNING]` or `[SECURITY CRITICAL] redis pubsub publish failed: <err>` and **degrade gracefully to local-only delivery**.
  - Messages and notifications sent on Instance A are still delivered to all clients locally connected to Instance A, ensuring single-replica deployments and temporary Redis outages do not crash connection loops or drop local messages.

### 4. Backward Compatibility & Rollback Plan
- Single-instance local deployments (the default in `docker-compose.yml`) operate identically with zero behavior change.
- If Redis connection fails during service startup, `notification-service` and `chat-service` log a prominent startup warning (`[WARN] Redis Pub/Sub initialization failed - falling back to single-instance local hub mode`) and proceed running in local-only hub mode.

### 5. Multi-Instance Test Strategy
- Multi-replica behavior is tested in a single test binary without requiring multiple OS processes by leveraging `github.com/alicebob/miniredis/v2`.
- A miniredis server is started in the test, and two distinct `Hub` (or `SSEHub`) instances are created sharing the miniredis address (matching the `TestTrackJob_RedisBackedIdempotency_MultiInstanceAndTTL` pattern in `user-service`).
- Test asserts that a message broadcast on Hub 1 is published via Redis Pub/Sub and received by a client connected to Hub 2.

## Consequences
- **Positive**: Eliminates silent message and notification loss when scaling `chat-service` and `notification-service` to 2 or more replicas.
- **Resource Footprint**: Minimal overhead; Redis Pub/Sub connection per instance with zero disk persistence overhead. Dynamic subscribe/unsubscribe in `chat-service` ensures instances only listen to active channels.
- **Deferred**: Message persistence / historical offline message delivery remains handled by MongoDB (`chat_messages` collection).

## Known Limitations

### 1. `notification-service` Redis Pub/Sub Self-Delivery Dependency
- **Context**: In `notification-service` (`services/notification-service/internal/hub/hub.go`), `Broadcast()` publishes payloads to Redis Pub/Sub channels (`notify:tenant:<id>` and `notify:global`) when Redis is enabled, relying on the instance's own pattern subscription (`PSubscribe("notify:*")`) to loop messages back to locally connected clients.
- **Tradeoff**: Every notification — including delivery to clients on the originating instance — incurs a full Redis network round-trip. `rdb.Publish()` confirming success only guarantees Redis received the payload; if the publishing instance's subscriber connection experiences a transient network hiccup, local clients on the origin replica could miss the alert without a surfaced error.
- **Forward Pointer / Recommended Remediation**: Future contributors can call `deliverLocal(n)` immediately on the origin instance (fast in-process path) in addition to `rdb.Publish()`, paired with de-duplication on the subscriber loop via `Notification.ID` tracking.

## Alternatives Considered
- **NATS / Kafka / RabbitMQ**: Rejected to avoid introducing a new infrastructure dependency; Redis is already established in the codebase and infrastructure for rate-limiting and idempotency (`shared/infra/ratelimit`).
- **Global Pub/Sub Channel for Chat**: Having every instance subscribe to a single `chat:pubsub:all` channel was considered but rejected in favor of dynamic per-channel subscription (`chat:channel:<name>`), preventing instances from receiving message traffic for channels with zero local subscribers.
