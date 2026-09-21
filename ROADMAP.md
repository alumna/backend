# Alumna Backend Roadmap & Architectural Rationale

This document outlines the strategic roadmap for the Alumna Backend framework leading up to v1.0. 

**Context & Direction:** 
The official MongoDB adapter is available ([alumna/mongodb](https://github.com/alumna/mongodb) **0.9.0**). Backend cache, rate-limit ports, Redis shard, and native WebSockets are released. The `after_commit` hook is available. NATS.io WebSocket fan-out is now possible as an application logic combining [Alumna NATS](https://github.com/alumna/nats). Mail send port (5.3) is in this source (unreleased, target 0.10.0). Amazon SES is the `alumna-ses` shard. Relational database adapters (MySQL, PostgreSQL) remain on the roadmap but have been moved to later phases.

Every phase below includes not just *what* needs to be built, but the *rationale* behind how it must integrate with Alumna's strict, zero-allocation, 100% test-coverage philosophy.

---

## Phase 1: Core Resilience & MongoDB Native Support (v0.6)
*Goal: Prepare the framework for NoSQL/Document databases and enterprise delivery, ensuring the testing suite and core interfaces are database-agnostic.*
**Status:** done (1.1–1.5)

### 1.1 Make the `AdapterSuite` ID-Agnostic
**Status:** done (0.5.10)

`AdapterSuite.run(name, expect_incremental_ids: true)` — default `true` keeps SQLite and MemoryAdapter asserts (`"1"`, `"2"`, concurrent `1..N`). Pass `false` for opaque string ids: non-empty unique strings, ignore a client-supplied `id`, no integer parsing.

### 1.1b AdapterSuite mixed-sort mode
**Status:** done (0.5.10)

`AdapterSuite.run(..., mixed_sort: :sql)`. Default `:sql` keeps SQLite and MemoryAdapter mixed `metadata` order (`2`, `"10"`, `[1]` → `[2, "10", [1]]`). Pass `:bson` for MongoDB native order (arrays by min element: `[[1], 2, "10"]`). MemoryAdapter stays SQLite-like. The suite is the Service contract, not a freeze of SQLite storage classes.

### 1.2 Standardize Index Generation
**Status:** done (0.5.10)

`Alumna::Service` has `def create_indexes! : Nil; end`. Adapters override it. Apps can run `app.services.each_value(&.create_indexes!)` at boot. `MemoryAdapter` uses the no-op.

### 1.3 Pluggable Formats Expansion & The `ObjectId` Defense
**Status:** done (0.6.0)

Built-in `:object_id` format: 24 hex characters (`0-9`, `a-f`, `A-F`). Same rules as BSON ObjectId hex. The backend does not depend on bson.cr. Apps can set `.str("id", format: :object_id)` (or another body field) for 422 on invalid hex in the body. Path `ctx.id` is still the adapter (bad hex is 404 / nil, not 422).

### 1.4 Global Query Limitations (`$limit` Cap)
**Status:** done (0.6.0)

`app.default_query_limit` and `app.max_query_limit` (both nil by default). Query applies them after parse so adapters see a clamped `q.limit`. Nil means no cap. If the client omits `$limit` and default is set, that default is used. If a limit exists and max is set, Query clamps to max. Max does not invent a limit. Invalid `$limit` / `$skip` is 400. Adapter `max_limit` may still clamp; the effective limit is the tighter one.

### 1.5 The Official Alumna MongoDB Adapter
**Status:** done (published at [alumna/mongodb](https://github.com/alumna/mongodb) **0.9.0**)

Official `Alumna::MongoAdapter` against MongoDB 8.0. Driver is cryomongo (Crystal 1.21, MongoDB 8.x). Alumna `id` is a 24-character hex string. MongoDB `_id` is ObjectId. Do not store both. `update` is `replace_one`. `patch` is `$set` (dotted schema paths allowed) and optional `$unset`. Query uses `typed_filters`. Native array `$eq` / `$ne` / `$in` / `$nin`. AdapterSuite flags: `expect_incremental_ids: false`, `mixed_sort: :bson`. `#transaction` shipped in **0.8.2**. `#watch` shipped in **0.9.0** (replica set). Next adapter work is GridFS, then client-side encryption after the driver has CSFLE.

---

## Phase 2: Security, Authentication & Error Propagation (v0.7)
*Goal: First-class, zero-allocation authentication primitives and robust internal routing.*
**Status:** done (2.1–2.2)

### 2.1 Context Error Propagation
**Status:** done (tuple return in 0.5.8; uncaught rule Exception wrap in 0.7)

*   **The Problem:** An internal service failure used to leave `ctx.call` as a generic Crystal `Exception`.
*   **The Solution:** `ctx.call` returns `{ServiceResult, ServiceError?}`. The parent inspects `err` and can return a new `ServiceError`. `ServiceError` is a struct. It is not an `Exception`. `App#dispatch` converts an uncaught `Exception` from a rule into `ServiceError.internal`. The HTTP status is 500. The body is JSON.
*   **Rationale:** The parent can translate a child error (for example 404 to 422) without a 500 crash. Expected API errors do not allocate an exception backtrace.

### 2.2 Built-in Authentication Rules
**Status:** done (0.7.0)

*   **The Solution:** Built-in rules for session cookies (`Alumna::Session` + `MemorySessionStore`) and JWT HS256 (`Alumna.jwt` / `Alumna::JWT.encode`). Session store-down is `ServiceError.internal`, not 401. `start` / `stop` / `rotate` return `T | StoreError`.
*   **Rationale:** Official, tested auth rules reduce boilerplate. `SessionStore` is a public type so a Redis adapter can drop in later. JWT is HS256 only: Crystal 1.21 stdlib has HMAC and no RSA key type.

---

## Phase 3: Distributed State & Caching (v0.8)
*Goal: Share session, rate-limit, and cache state across processes.*
**Status:** backend ports done. Redis shard: Cache, session, and rate limit done in `alumna-redis`.

### 3.1 Extract `RateLimitStore` Interface
**Status:** done

*   **The Problem:** The RateLimiter rule used a private in-memory store. In a multi-instance deployment, rate limits must be shared across servers.
*   **The Solution:** Public abstract `Alumna::RateLimitStore`. `MemoryRateLimitStore` is the default. `Alumna.rate_limit` takes `store:`. `hit` returns `{count, reset_at} | StoreError`. Memory never returns `StoreError`. Store-down in the rule is `ServiceError.internal` (fail closed).
*   **Rationale:** A Redis store can implement `hit` and drop in. The rule API stays the same.

### 3.2 Store-neutral Cache
**Status:** done

*   **The Problem:** `find` and `get` results lived only in the service adapter. Multi-process apps need a shared byte store.
*   **The Solution:** Public `Alumna::Cache` and `MemoryCache`. Rule `Alumna.cache` for `get` and `find`. Get uses one key per id: write-through `set`, miss fill `set_nx`, `delete` on remove. Find uses a collection generation (`incr` on write). Old find keys expire by TTL. The app names `Cache`, not Redis. `get` is `Bytes? | StoreError` (bytes = hit, nil = miss, Error = down). Memory never returns `StoreError`. Store-down in the rule is `ServiceError.internal`. No fill. No write-through.
*   **Rationale:** A Redis or Memcached shard implements the same methods. The rule stays in the backend.

### 3.3 Official Redis shard
**Status:** done in `alumna-redis`: `RedisCache`, `RedisSessionStore`, `RedisRateLimitStore`, and GitHub CI.

*   **The Solution:** Shard `alumna-redis`. `Alumna::Redis.new(uri)` gives `.cache` (`RedisCache`), `.session_store` (`RedisSessionStore`), and `.rate_limit_store` (`RedisRateLimitStore`). Apps attach `Alumna.cache(redis.cache, ttl:)`, `Alumna.session(redis.session_store)`, and `Alumna.rate_limit(store: redis.rate_limit_store)`. One `Redis::Client` per process. Not a Service adapter. No `AdapterSuite`. Port methods return backend `StoreError` on driver failure. Holder `new` / `from_uri` / `from_env` / `ping` / `close` return `T | Alumna::Redis::Error` (struct).
*   **Rationale:** `SessionStore`, `RateLimitStore`, and `Cache` already exist. Redis implements them so several Alumna processes can share state.

---

## Phase 4: Real-time Transports (v0.9)
*Goal: Enable bi-directional communication leveraging Crystal's lightweight fibers.*
**Status:** done

### 4.1 Native WebSockets
**Status:** done

*   **The Solution:** Upgrade the HTTP Router to natively detect and negotiate WebSocket (`ws://` / `wss://`) connections. JSON frames call `App#dispatch` on the same services as REST.
*   **Integration:** When a connection is established via WebSocket, the router sets `ctx.provider = "websocket"`. Handshake headers are copied onto every frame.
*   **Rationale:** Real-time applications require push semantics. Alumna's pipeline and rule architecture is already agnostic to the transport layer. A WebSocket connection will route payloads through the exact same Services and Schemas as HTTP REST.

### 4.2 Stateful Connections
**Status:** done

*   **The Solution:** Persist `ctx.store` across WebSocket frames. `App#connections` (`MemoryConnections`) can send to one id or a local topic. Delivery is this process only.
*   **Rationale:** If a user authenticates on connection, their `User` object is saved to the store. Subsequent messages sent over that WebSocket should not need to undergo JWT parsing or database lookups again; the pipeline should inherit the stateful store. Cross-process fan-out is Phase 5.2.

---

## Phase 5: Event Bus & Messaging (v0.10)
*Goal: Reactive architecture across horizontally scaled instances.*
**Status:** 5.1 done. 5.2 done. 5.3 port is in this source (unreleased, target 0.10.0).

### 5.1 The `after_commit` Hook
**Status:** done

*   **The Problem:** The `after` hook runs immediately after the service method. If a later transaction rolls back, an event from `after` is incorrect.
*   **The Solution:** Distinct `RulePhase::AfterCommit` and `after_commit` on App and Service. Same `Rule` type and `on:` as `after`. `App#dispatch` runs AfterCommit after a successful After pipeline, only if the service method ran. A cache hit or a before-rule that set `ctx.result` skips it. A successful `remove` still runs it. Order is service then app. `on: :mutate` is create, update, patch, and remove. Cache and logger stay on After.
*   **Commit in this version:** The adapter already returned from the service method (typical autocommit). There is no request transaction around `dispatch`. There is no `MongoAdapter#transaction` hook.
*   **Errors:** AfterCommit `ServiceError` or an uncaught Exception uses the error pipeline. The write already happened. The client sees an error.
*   **Mongo `#transaction`:** That API wraps adapter CRUD on the fiber. If `dispatch` or `ctx.call` runs inside the block, AfterCommit still runs before the block commits. Those apps publish after the block.
*   **Rationale:** Apps that autocommit in the method can publish from `after_commit` without a cache-hit event. A later request-scoped transaction can wrap method + After. AfterCommit stays after that commit.

### 5.2 NATS.io Integration & WebSocket Fan-out
**Status:** done

*   **The Solution:** Official [Alumna NATS](https://github.com/alumna/nats) shard. The application composes it with local `Connections`. `after_commit` (with `on: :mutate`) publishes successful mutations (`created`, `updated`, `patched`, `removed`). Each process that holds sockets subscribes with no queue group and calls `connections.send_topic`. Backend does not import NATS. The NATS shard does not import HTTP WebSocket. See `examples/websocket_fanout.cr` in alumna-nats.
*   **Rationale:** In a scaled deployment, Instance A might process a `PATCH /posts/1` request. Instance B might hold the active WebSocket connection for the user viewing that post. Instance A publishes the mutation to NATS; Instance B subscribes to NATS, receives the mutation, and pushes the payload directly down the WebSocket to the client. This achieves stateless, horizontally scaled real-time sync.

### 5.3 Mail send port
**Status:** in this source (unreleased, target 0.10.0). SES delivery is the `alumna-ses` shard.

*   **The Problem:** Apps need to send mail (verify links, receipts). Specs must not hit Amazon SES or SMTP. Backend must not depend on AWS.
*   **The Solution:** Public `Alumna::Mail`, abstract `Alumna::Mailer`, `Alumna::MemoryMailer`, and `Alumna::MailError` in this repository. `send` returns `Nil | MailError`. Memory never returns `MailError`. `delivered` returns copies. Empty `from`, empty `to`, or empty `subject` raises `ArgumentError`. Official shard `alumna-ses` implements `Mailer` as `Alumna::SES`. No built-in `Alumna.mail` rule in the first mail release. SMTP is a later shard.
*   **Rationale:** Same split as `SessionStore` / `alumna-redis`. The port stays in Backend so specs stay fake. AWS stays in a shard.

---

## Phase 6: Relational Ecosystem (v0.11+)
*Goal: Expand ecosystem for traditional SQL deployments.*

### 6.1 MySQL & PostgreSQL Adapters
*   **The Solution:** Build official drivers for enterprise SQL engines.
*   **Rationale:** The foundational architecture for this is already proven by the `SqliteAdapter`. The core concepts—zero-allocation JSON streaming, strict schema-based SQL injection prevention, and mapping nested dot-notation to JSONB columns—will map cleanly to PostgreSQL and MySQL when the time comes.
