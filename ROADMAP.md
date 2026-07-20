# Alumna Backend Roadmap & Architectural Rationale

This document outlines the strategic roadmap for the Alumna Backend framework leading up to v1.0. 

**Context & Direction:** 
Now the immediate focus is on distributed NoSQL capabilities, real-time WebSockets, horizontal scaling via Redis, and event-driven architecture via NATS.io. Relational database adapters (MySQL, PostgreSQL) remain on the roadmap but have been moved to later phases.

Every phase below includes not just *what* needs to be built, but the *rationale* behind how it must integrate with Alumna's strict, zero-allocation, 100% test-coverage philosophy.

---

## Phase 1: Core Resilience & MongoDB Native Support (v0.6)
*Goal: Prepare the framework for NoSQL/Document databases and enterprise delivery, ensuring the testing suite and core interfaces are database-agnostic.*

### 1.1 Make the `AdapterSuite` ID-Agnostic
*   **The Problem:** Currently, `Alumna::Testing::AdapterSuite` asserts that newly created records return `record["id"] == "1"` and auto-increment. MongoDB uses 24-character hex strings (`ObjectId`). Running the current suite against a MongoDB adapter would force the adapter to fake an auto-incrementing integer collection, which is a severe anti-pattern.
*   **The Solution:** Refactor the `AdapterSuite` to assert that the generated `id` is present, is a non-empty `String` (inside the `AnyData` payload), is unique, and can be used to successfully retrieve the record via `get`. 
*   **Implementation Note:** Add an optional configuration flag to the suite macro (e.g., `expect_incremental_ids: true`) so that relational adapters like SQLite and Memory can still rigorously test their auto-increment logic.

### 1.2 Standardize Index Generation
*   **The Problem:** `create_indexes!` is currently a custom method specific to the `SqliteAdapter`. MongoDB heavily relies on programmatic index creation (unique, compound, and sparse indexes).
*   **The Solution:** Add an empty `def create_indexes! : Nil; end` to the base `Alumna::Service` class.
*   **Rationale:** This allows the host application to effortlessly iterate over all mounted services at boot (`app.services.values.each(&.create_indexes!)`) and initialize schema constraints universally, regardless of the underlying database engine.

### 1.3 Pluggable Formats Expansion & The `ObjectId` Defense
*   **The Problem:** If a client requests `GET /users/invalid-id`, the adapter currently passes it as a String. If this string is passed to a MongoDB driver and it attempts to cast it to a `BSON::ObjectId`, the driver will raise a fatal Exception, resulting in a 500 Internal Server Error instead of a 400/404.
*   **The Solution:** Introduce a new built-in format, `:object_id` (or `:bson_id`), to `Alumna::Formats`. 
*   **Rationale:** Developers can declare `.str("id", format: :object_id)` in their schemas. This ensures Alumna validates the hex string format at the HTTP boundary, failing fast with a 422 before the MongoDB driver is ever invoked.

### 1.4 Global Query Limitations (`$limit` Cap)
*   **The Problem:** Currently, a malicious client could pass `?$limit=1000000`, potentially causing an Out-Of-Memory (OOM) scenario when the adapter attempts to serialize a massive dataset.
*   **The Solution:** Introduce `app.default_query_limit` and `app.max_query_limit`.
*   **Rationale:** Security. Even if an adapter handles streaming natively, the framework must enforce an absolute upper bound on query sizes to protect the memory footprint of the Crystal process.

### 1.5 The Official Alumna MongoDB Adapter
*   **Driver Strategy:** Writing a MongoDB driver from scratch is notoriously difficult due to SDAM (Server Discovery and Monitoring) and SCRAM-SHA Auth handshakes. Instead, we will fork `cryomongo`, upgrade it to Crystal 1.20, ensure thread-safety (`Sync::Mutex` vs `Mutex`), strip out unused legacy bloat, and test it against MongoDB 8.x.
*   **`id` vs `_id` Mapping:** MongoDB strictly stores `_id`. Alumna strictly exposes `id` (as a String). The adapter must intercept data at the boundary (`cast_to_db` / `cast_from_db`) to translate `id` to `{"_id": BSON::ObjectId(ctx.id)}`. Do *not* store both `id` and `_id` in the database.
*   **Patch vs Update Semantics:** 
    *   `update` must replace the entire document.
    *   `patch` must translate to MongoDB's `$set` operator, rather than replacing the document. 
    *   *Constraint:* For v1 of the adapter, we will explicitly block dot-notation in `patch` payload keys to maintain strict compliance with the current `AdapterSuite`. We will unlock nested dot-notation patching in a future release.
*   **BSON Casting & Filter Translation:** 
    *   Leverage `Query#typed_filters`. 
    *   Map `Op::Eq` and `Op::In` directly. 
    *   Map `Op::Ne` to `$ne`. *Crucial constraint:* Respect the `MemoryAdapter` semantics—when applying `$ne` to an array, it means *none* of the elements equal the value. MongoDB natively handles this, but it must be tested rigorously.
    *   Map Alumna `Time` to BSON `Date`, and `Bytes` to BSON `Binary`.

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
