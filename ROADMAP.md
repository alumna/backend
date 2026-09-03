# Alumna Backend Roadmap & Architectural Rationale

This document outlines the strategic roadmap for the Alumna Backend framework leading up to v1.0. 

**Context & Direction:** 
Now the immediate focus is on distributed NoSQL capabilities, real-time WebSockets, horizontal scaling via Redis, and event-driven architecture via NATS.io. Relational database adapters (MySQL, PostgreSQL) remain on the roadmap but have been moved to later phases.

Every phase below includes not just *what* needs to be built, but the *rationale* behind how it must integrate with Alumna's strict, zero-allocation, 100% test-coverage philosophy.

---

## Phase 1: Core Resilience & MongoDB Native Support (v0.6)
*Goal: Prepare the framework for NoSQL/Document databases and enterprise delivery, ensuring the testing suite and core interfaces are database-agnostic.*
**Status:** done (1.1–1.5)

### 1.1 Make the `AdapterSuite` ID-Agnostic
**Status:** done (Unreleased after 0.5.9)

`AdapterSuite.run(name, expect_incremental_ids: true)` — default `true` keeps SQLite and MemoryAdapter asserts (`"1"`, `"2"`, concurrent `1..N`). Pass `false` for opaque string ids: non-empty unique strings, ignore a client-supplied `id`, no integer parsing.

### 1.1b AdapterSuite mixed-sort mode
**Status:** done (Unreleased after 0.5.9)

`AdapterSuite.run(..., mixed_sort: :sql)`. Default `:sql` keeps SQLite and MemoryAdapter mixed `metadata` order (`2`, `"10"`, `[1]` → `[2, "10", [1]]`). Pass `:bson` for MongoDB native order (arrays by min element: `[[1], 2, "10"]`). MemoryAdapter stays SQLite-like. The suite is the Service contract, not a freeze of SQLite storage classes.

### 1.2 Standardize Index Generation
**Status:** done (Unreleased after 0.5.9)

`Alumna::Service` has `def create_indexes! : Nil; end`. Adapters override it. Apps can run `app.services.each_value(&.create_indexes!)` at boot. `MemoryAdapter` uses the no-op.

### 1.3 Pluggable Formats Expansion & The `ObjectId` Defense
**Status:** done (Unreleased after 0.5.10)

Built-in `:object_id` format: 24 hex characters (`0-9`, `a-f`, `A-F`). Same rules as BSON ObjectId hex. The backend does not depend on bson.cr. Apps can set `.str("id", format: :object_id)` (or another body field) for 422 on invalid hex in the body. Path `ctx.id` is still the adapter (bad hex is 404 / nil, not 422).

### 1.4 Global Query Limitations (`$limit` Cap)
**Status:** done (Unreleased after 0.5.10)

`app.default_query_limit` and `app.max_query_limit` (both nil by default). Query applies them after parse so adapters see a clamped `q.limit`. Nil means no cap. If the client omits `$limit` and default is set, that default is used. If a limit exists and max is set, Query clamps to max. Max does not invent a limit. Invalid `$limit` / `$skip` is 400. Adapter `max_limit` may still clamp; the effective limit is the tighter one.

### 1.5 The Official Alumna MongoDB Adapter
**Status:** done (published at [alumna/mongodb](https://github.com/alumna/mongodb))

Official `Alumna::MongoAdapter` against MongoDB 8.0. Driver is cryomongo (Crystal 1.21, MongoDB 8.x). Alumna `id` is a 24-character hex string. MongoDB `_id` is ObjectId. Do not store both. `update` is `replace_one`. `patch` is `$set` (dotted schema paths allowed) and optional `$unset`. Query uses `typed_filters`. Native array `$eq` / `$ne` / `$in` / `$nin`. AdapterSuite flags: `expect_incremental_ids: false`, `mixed_sort: :bson`. Transactions and change streams are later adapter work, not this phase.

---

## Phase 2: Security, Authentication & Error Propagation (v0.7)
*Goal: First-class, zero-allocation authentication primitives and robust internal routing.*

### 2.1 Context Error Propagation
*   **The Problem:** Currently, if `ctx.call` triggers an internal service and that service fails (e.g., validation fails), `ctx.call` raises a generic Crystal `Exception`.
*   **The Solution:** Ensure internal `ctx.call` failures propagate the actual `ServiceError` struct up the chain.
*   **Rationale:** By raising/returning the typed `ServiceError`, the parent service can cleanly `rescue` it and translate it into an intelligent response, rather than crashing the pipeline with a 500 error.

### 2.2 Built-in Authentication Rules
*   **The Solution:** Implement built-in rules for JWT (JSON Web Tokens) verification and Session parsing.
*   **Rationale:** While the framework makes writing custom authentication easy, providing official, heavily-tested, zero-allocation auth rules ensures community standardization and reduces boilerplate for enterprise deployments.

---

## Phase 3: Distributed State & Caching (v0.8)
*Goal: Prepare the framework for horizontal scaling by extracting memory-bound state.*

### 3.1 Extract `RateLimitStore` Interface
*   **The Problem:** The current `RateLimiter` rule uses a brilliant, monotonic, in-memory store. However, in a multi-instance deployment, rate limits must be shared across servers.
*   **The Solution:** Extract the core logic into an abstract `Alumna::RateLimitStore` interface.
*   **Rationale:** This decoupling allows the framework to easily swap the in-memory store for a `RedisRateLimitStore` without changing the rule's public API.

### 3.2 Alumna Redis Adapter
*   **The Solution:** Build a Redis adapter to act as the distributed backbone.
*   **Rationale:** Beyond rate-limiting, a Redis adapter will provide an `Alumna::RedisCache` helper. This will allow developers to memoize expensive `find` and `get` operations, with the adapter automatically and transparently invalidating specific cache keys during `create`, `update`, `patch`, and `remove` operations.

---

## Phase 4: Real-time Transports (v0.9)
*Goal: Enable bi-directional communication leveraging Crystal's lightweight fibers.*

### 4.1 Native WebSockets
*   **The Solution:** Upgrade the HTTP Router to natively detect and negotiate WebSocket (`ws://` / `wss://`) connections. 
*   **Integration:** When a connection is established via WebSocket, the router will dynamically set `ctx.provider = "websocket"`.
*   **Rationale:** Real-time applications require push semantics. Alumna's pipeline and rule architecture is already agnostic to the transport layer. A WebSocket connection will route payloads through the exact same Services and Schemas as HTTP REST.

### 4.2 Stateful Connections
*   **The Solution:** Allow the framework to persist a connection's state (specifically the `ctx.store`) across multiple WebSocket frames.
*   **Rationale:** If a user authenticates on connection, their `User` object is saved to the store. Subsequent messages sent over that WebSocket should not need to undergo JWT parsing or database lookups again; the pipeline should inherit the stateful store.

---

## Phase 5: Event Bus & Messaging (v0.10)
*Goal: Reactive architecture across horizontally scaled instances.*

### 5.1 The `after_commit` Hook
*   **The Problem:** Currently, the `after` hook runs immediately after the service method. If we introduce database transactions in the future, emitting an event in an `after` hook could result in a false positive if the transaction subsequently rolls back.
*   **The Solution:** Introduce a distinct `after_commit` hook phase (or an event-bus specific hook).
*   **Rationale:** We need a bulletproof guarantee that an event is only broadcasted to the system *if and only if* the data is permanently persisted.

### 5.2 NATS.io Integration & WebSocket Fan-out
*   **The Solution:** Build official integration with NATS.io to publish successful mutations (`created`, `updated`, `patched`, `removed`).
*   **Rationale:** In a scaled deployment, Instance A might process a `PATCH /posts/1` request. Instance B might hold the active WebSocket connection for the user viewing that post. Instance A publishes the mutation to NATS; Instance B subscribes to NATS, receives the mutation, and pushes the payload directly down the WebSocket to the client. This achieves stateless, horizontally scaled real-time sync.

---

## Phase 6: Relational Ecosystem (v0.11+)
*Goal: Expand ecosystem for traditional SQL deployments.*

### 6.1 MySQL & PostgreSQL Adapters
*   **The Solution:** Build official drivers for enterprise SQL engines.
*   **Rationale:** The foundational architecture for this is already proven by the `SqliteAdapter`. The core concepts—zero-allocation JSON streaming, strict schema-based SQL injection prevention, and mapping nested dot-notation to JSONB columns—will map cleanly to PostgreSQL and MySQL when the time comes.
