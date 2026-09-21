![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/alumna/backend/ci.yml) [![codecov](https://codecov.io/gh/alumna/backend/graph/badge.svg?token=GX1Z8DNR3W)](https://codecov.io/gh/alumna/backend) ![Dynamic YAML Badge](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Falumna%2Fbackend%2Frefs%2Fheads%2Fmaster%2Fshard.yml&query=version&prefix=v&label=version) ![GitHub License](https://img.shields.io/github/license/alumna/backend)

# Alumna

A minimalist, service-oriented backend framework for [Crystal](https://crystal-lang.org), inspired by Service Oriented Architecture (SOA) from frameworks like FeathersJS and designed around three ideas: simplicity, explicitness, and performance.

## Backend can be simple

```crystal
require "alumna"

# Schema definition
MessageSchema = Alumna::Schema.new
  .str("body", min_length: 1, max_length: 500)
  .str("author", min_length: 1)
  .bool("read", required: false)

# Authentication rule
Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "Bearer my-secret" ? nil : Alumna::ServiceError.unauthorized
end

app = Alumna::App.new

# Messages service based on Memory adapter
app.use "/messages", Alumna.memory(MessageSchema) {
  before Authenticate
  before validate, on: :write
}

# Done
app.listen(3000) # binds to 127.0.0.1:3000 by default
```

---

## Table of Contents
- [Philosophy](#philosophy)
- [Status](#status)
- [Installation](#installation)
- [Core Architecture](#core-architecture)
- [1. Services](#1-services)
    - [HTTP Routing Mapping](#http-routing-mapping)
    - [Querying](#querying)
        - [Query limit caps](#query-limit-caps)
    - [Database Adapters](#database-adapters)
    - [Writing a Custom Adapter](#writing-a-custom-adapter)
    - [Inter-Service Communication](#inter-service-communication)
- [2. Schemas](#2-schemas)
    - [Nested Fields](#nested-fields-objects-and-arrays)
    - [Default Values and Nullability](#default-values-and-nullability)
    - [Indexes and Unique Constraints](#indexes-and-unique-constraints)
    - [Conditional Requirements](#conditional-requirements)
    - [Strict Validation and Read-Only Fields](#strict-validation-and-read-only-fields)
    - [Pluggable Formats](#pluggable-formats)
- [3. Rules](#3-rules)
    - [Defining Rules](#defining-rules)
    - [Execution Order & Hooks](#execution-order--hooks)
    - [After commit](#after-commit)
    - [Targeting Methods with `on:`](#targeting-methods-with-on)
    - [The Rule Context](#the-rule-context)
    - [Headers, Params, and Views](#headers-params-and-views)
- [4. Built-in Rules](#4-built-in-rules)
    - [Validation](#validation)
    - [Timestamp](#timestamp)
    - [CORS](#cors)
    - [Logger](#logger)
    - [Rate Limiter](#rate-limiter)
    - [Cache](#cache)
    - [Session](#session)
    - [JWT](#jwt)
- [5. Server Configuration & Multi-threading](#5-server-configuration--multi-threading)
    - [Multi-threading and Workers](#multi-threading-and-workers)
    - [Unix Sockets & Local Providers](#unix-sockets--local-providers)
    - [WebSockets](#websockets)
    - [Graceful Shutdown](#graceful-shutdown)
    - [Trusted Proxies](#trusted-proxies)
- [Developer Experience](#developer-experience)
- [Full Example](#full-example)
- [Serialization](#serialization)
- [Testing](#testing)
- [Roadmap](#roadmap)
- [Design Decisions and Trade-offs](#design-decisions-and-trade-offs)
- [Contributing](#contributing)
- [License](#license)

---

## Philosophy

Most backend frameworks ask you to learn their full architecture before you can write a single working endpoint. Alumna takes the opposite approach.

The entire model fits in your head at once. There is no magic, no dependency injection container, no decorator metadata, and no complex resolver chain. Every moving piece is visible and explicit. A developer new to the codebase can read a service definition and understand the full execution path in minutes.

Alumna inherits Crystal's performance characteristics: ahead-of-time compilation, a single self-contained binary, no runtime dependencies, and throughput that benchmarks consistently alongside Go and Rust, all with a syntax beautifully close to Ruby.

---

## Status

Alumna is in early development, but moving fast. The core is complete and tested: HTTP REST, the rule pipeline (`before`, `after`, `after_commit`, `error`), schemas, queries, in-memory persistence, JSON, and MessagePack.

Official database adapters:
- [SQLite](https://github.com/alumna/sqlite)
- [MongoDB](https://github.com/alumna/mongodb).

Built-in rules include session, JWT HS256, rate limit, and cache. Session, rate limit, and cache use store ports. In-memory stores ship in this repository.

Redis stores (`Cache`, `SessionStore`, `RateLimitStore`) are available with:
- [Alumna Redis](https://github.com/alumna/redis).

Native WebSockets landed. The `after_commit` hook is available. Cross-process WebSocket fan-out is application composition with [Alumna NATS](https://github.com/alumna/nats). See [Roadmap](#roadmap) for PostgreSQL and MySQL.

---

## Installation

Add Alumna to your `shard.yml`:

```yaml
dependencies:
  alumna:
    github: alumna/backend
```

Then run `shards install`. Require it in your project:

```crystal
require "alumna"
```

*Crystal 1.20.2 or later is required.*

---

## Core Architecture

Alumna's architecture revolves around three decoupled concepts:

1. **Services:** Objects that expose a standard set of data methods (`find`, `get`, `create`, `update`, `patch`, `remove`, `options`) and are automatically mounted as RESTful HTTP APIs. `options` is reserved for CORS preflights and has no business logic by default.
2. **Schemas:** Declarative definitions of data shapes, used for both strict input validation and structural hints for databases.
3. **Rules:** Single-responsibility functions (middlewares) that handle concerns like authentication, logging, or rate-limiting. They run in a flat, predictable pipeline.

---

## 1. Services

A service in Alumna acts as a data adapter. You don't write "controllers" and "routes" manually. Instead, you mount a service to a path, and Alumna automatically wires up the HTTP REST verbs to the service's methods.

For simple resources, you can use the built-in `MemoryAdapter` block syntax:

```crystal
app.use "/messages", Alumna.memory(MessageSchema) do
  before Authenticate
  after AddRequestId
end
```

If you need to override business logic, you can define a full class:

```crystal
class UserService < Alumna::MemoryAdapter
  def initialize
    super(UserSchema)
    before validate, on: :write
  end

  def find(ctx)
    # custom find logic here
    super
  end
end

app.use "/users", UserService.new
```

### HTTP Routing Mapping

When a service is mounted, Alumna exposes it automatically following standard REST conventions:

| HTTP Verb | Path | Service Method |
|---|---|---|
| `GET` | `/users` | `find` |
| `GET` | `/users/:id` | `get` |
| `POST` | `/users` | `create` |
| `PUT` | `/users/:id` | `update` |
| `PATCH` | `/users/:id` | `patch` |
| `DELETE` | `/users/:id` | `remove` |
| `OPTIONS` | `/users` or `/users/:id` | `options` |

### Querying

Alumna automatically parses URL query strings into a `ctx.query` object. It natively supports MongoDB/FeathersJS-style comparison operators and nested dot-notation.

Because URL parameters are inherently strings, Alumna provides a powerful `typed_filters(schema)` method. It reads your service's schema and automatically coerces the query values into native Crystal types (`Int64`, `Float64`, `Bool`, `Time`), returning an immediate `400 Bad Request` if the client sends a malformed type.

```crystal
# GET /users?age[$gte]=18&status[$in]=active,pending&billing.plan=pro&$limit=10&$sort=age:-1

# Raw string parsed from URL
ctx.query.filters["age"] # => [{op: Op::Gte, value: "18"}]

# Strictly typed against the UserSchema
filters = ctx.query.typed_filters(schema)
filters["age"]          # => [{op: Op::Gte, value: 18_i64}]
filters["status"]       # => [{op: Op::In, value: ["active", "pending"]}]
filters["billing.plan"] # => [{op: Op::Eq, value: "pro"}]

ctx.query.limit # => 10
ctx.query.sort  # => [{"age", -1}]
```

**Supported operators:** `$eq` (default), `$ne`, `$gt`, `$gte`, `$lt`, `$lte`, `$in`, `$nin`.

### Query limit caps

`app.default_query_limit` and `app.max_query_limit` are optional. Both default to `nil` (no cap).

```crystal
app = Alumna::App.new
app.default_query_limit = 50
app.max_query_limit = 200
```

- If the client omits `$limit` and `default_query_limit` is set, Query uses that default.
- If a limit is present (client or default) and `max_query_limit` is set, Query clamps to max.
- If both are set, the tighter value wins.
- If the client omits `$limit` and default is `nil`, there is no limit, even when max is set.
- Invalid `$limit` or `$skip` (not a non-negative integer) is `400`. `$limit=0` is valid (zero rows).
- Negative App options raise `ArgumentError` at config time.

Query applies these caps after parse. Adapters read the already-clamped `ctx.query.limit`.

The MongoDB adapter constructor still has `max_limit`. Both may clamp. The effective limit is the tighter of App max and adapter max.

### Database Adapters

Alumna ships with a built-in `MemoryAdapter` out of the box, perfect for prototyping and rapid testing.

For real persistence, use one of our official database adapters. They translate Alumna schemas and queries into store operations.

- **SQLite:** [`alumna/sqlite`](https://github.com/alumna/sqlite) - Official SQLite adapter. Zero-allocation JSON streaming for nested fields, native dot-notation on JSON columns, and schema checks that block SQL injection.
- **MongoDB:** [`alumna/mongodb`](https://github.com/alumna/mongodb) - Official MongoDB 8.0 adapter. MongoDB stores `_id` as ObjectId. Alumna exposes `id` as a 24-character hex string. Use `Alumna.mongo(client, database, collection, schema)`. Opt-in `#transaction` and `#watch` need a replica set. For `AdapterSuite`, pass `expect_incremental_ids: false` and `mixed_sort: :bson`.

### Writing a Custom Adapter

To connect a real database manually, inherit from `Alumna::Service` and implement its six abstract methods. Each method receives the full `RuleContext` and returns a typed value. Override `create_indexes!` if the store needs indexes. The base method is a no-op.

```crystal
class PostgresUserService < Alumna::Service
  def initialize(@db : DB::Database)
    super(UserSchema)
    self.before(Authenticate)
  end

  def find(ctx : RuleContext) : Array(Hash(String, AnyData)) | ServiceError
    # 1. Safely coerce URL strings into native types
    filters = ctx.query.typed_filters(schema)
    return filters if filters.is_a?(ServiceError)
    
    # 2. Query @db using filters, ctx.query.limit, skip, and sort
    [] of Hash(String, AnyData)
  end

  def get(ctx : RuleContext) : Hash(String, AnyData)? | ServiceError
    # query @db using ctx.id
    nil
  end

  def create(ctx : RuleContext) : Hash(String, AnyData) | ServiceError
    # insert ctx.data into @db, return the created record
    {} of String => AnyData
  end

  def update(ctx : RuleContext) : Hash(String, AnyData) | ServiceError
    # full replace of ctx.id with ctx.data
    {} of String => AnyData
  end

  def patch(ctx : RuleContext) : Hash(String, AnyData) | ServiceError
    # partial update of ctx.id with ctx.data
    {} of String => AnyData
  end

  def remove(ctx : RuleContext) : Nil | ServiceError
    # delete record at ctx.id, return ServiceError.not_found if it didn't exist.
    # Returning `nil` here automatically triggers a 204 No Content response
    nil
  end
end
```

### Inter-Service Communication

Services often need to interact with each other (e.g., a `Post` creation triggering an `AuditLog` creation). Instead of making expensive HTTP calls to yourself or duplicating business logic, Alumna provides `ctx.call`.

`ctx.call` dispatches a request to another mounted service completely in-memory. It bypasses the network and serialization stack, but **still fully executes the target service's schema validations and rules**.

```crystal
CreateAuditLog = Alumna::Rule.new do |ctx|
  # Safely trigger another service entirely in-memory!
  result, error = ctx.call("/audit", :create, Alumna.hash(
    action: "User updated",
    user_id: ctx.id
  ))

  if error
    return Alumna::ServiceError.internal("Audit failed")
  end

  nil
end
```

**Automatc dynamic paths**
`ctx.call` resolves dynamic paths automatically and it is not necessary to split the path and the ID. You can use in the same way you would do an API call:

```crystal
ctx.call("/users/123", :patch)
````

And it has an optional `params:` argument that you can use to send filters.

**Per-call store extras**
`ctx.call` also accepts an optional `store:` hash. Those keys are written onto the child's store for that call only. The caller's `ctx.store` is never updated.

```crystal
extras = {} of String => Alumna::StoreType
extras["actor"] = "system"
ctx.call("/audit", :create, Alumna.hash(action: "created"), store: extras)
```

If the caller already has a store (for example after authentication), the extras are merged on top of a shallow copy. If the caller has no store, the given hash is used directly - child writes then alias that hash.

**How it is handled internally**
When you invoke `ctx.call`:
1. `ctx.provider` is set to `"internal"`.
2. The `ctx.store` from the parent request is **shallow-copied** to the new context. This means if a global rule authenticated a user and stored them in `ctx.store["current_user"]`, the internal service will automatically inherit that authenticated user, bypassing the need to re-validate tokens or hit the database twice.
3. If you pass `store:`, those keys overlay the copy (or become the child's store when the parent has none). Parent keys stay on the parent.

---

## 2. Schemas

A schema describes the fields a service works with. 

```crystal
UserSchema = Alumna::Schema.new
  .str("name",  min_length: 2, max_length: 100)
  .str("email", format: :email)
  .int("age")
  .bool("admin", required: false) # required is true by default
```

**Supported field types:** `:str`, `:int`, `:float`, `:bool`, `:time`, `:bytes`, `:nullable`, `:hash`, `:array` (or `Alumna::FieldType::Str`, etc.).

You can also use the more explicit `field` helper:

```crystal
UserSchema = Alumna::Schema.new
  .field("name",  :str, min_length: 2, max_length: 100)
  .field("email", :str, format: :email)
  .field("age",   :int)
```

**Supported constraints:** `required`, `required_on`, `min_length`, `max_length`, `format`

### Nested Fields (Objects and Arrays)

Alumna fully supports validating nested JSON structures. The validation engine walks the data tree using a zero-allocation path tracer, ensuring deep validation remains incredibly fast.

```crystal
OrganizationSchema = Alumna::Schema.new
  .str("name")
  .hash("billing") do |sub|
    sub.str("plan", min_length: 1)
    sub.str("card_last_four", min_length: 4, max_length: 4)
  end
  .array("tags", of: :str, min_length: 1, max_length: 10)
  .array("members") do |sub|
    sub.str("email", format: :email)
    sub.str("role")
  end
```

If a nested field fails validation, Alumna replies with explicit dot/bracket notation errors (e.g., `{"billing.plan": "is required"}`, or `{"members[0].email": "must be a valid email address"}`).

### Default Values and Nullability

Fields can define `default` values that the validation engine will automatically inject into `ctx.data` during `CREATE` operations if the client omits them. Defaults can be static values or dynamic blocks (Procs) evaluated at runtime.

```crystal
UserSchema = Alumna::Schema.new
  .str("email", format: :email)
  .str("status", default: "active")
  .time("created_at", default: -> { Time.utc.as(Alumna::AnyData) })
```

*Note: Because Crystal requires strict typing in Procs, dynamic defaults must explicitly cast their return value using `.as(Alumna::AnyData)`.*

By default, Alumna schemas do not allow explicit `null` values. If a field is optional (`required: false`), the client can omit the key entirely, but sending `"key": null` will result in a validation error. 

To explicitly allow `null` values in the payload, use the `nullable: true` trait:

```crystal
ProfileSchema = Alumna::Schema.new
  .str("username")
  .str("bio", required: false, nullable: true)
```

### Indexes and Unique Constraints

Because Alumna schemas act as the blueprint for database adapters, they support explicit index and uniqueness definitions. Adapters (SQLite, MongoDB, and later Postgres) can create indexes or enforce uniqueness from those traits.

You can apply `unique: true` or `indexed: true` directly to individual fields, including deeply nested hashes:

```crystal
AccountSchema = Alumna::Schema.new
  .str("email", unique: true)
  .str("tenant_id", indexed: true)
  .hash("profile") do |sub|
    sub.str("handle", unique: true) # Safely translates to a dot-notation index (profile.handle)
  end
```

For compound indexes spanning multiple fields, use the schema-level `.index` method:

```crystal
MembershipSchema = Alumna::Schema.new
  .str("user_id")
  .str("organization_id")
  .str("role")
  .index(["user_id", "organization_id"], unique: true)
  .index("role") # Shorthand for a single-field index
```

Adapters, including the built-in `MemoryAdapter`, read these traits to proactively reject conflicting payloads with a `422 Unprocessable Entity` ("already exists") before the conflict can corrupt your application state or trigger an unhandled SQL constraint exception.

Database adapters create these indexes in `create_indexes!`. `Alumna::Service` provides a no-op. At boot:

```crystal
app.services.each_value(&.create_indexes!)
```

`MemoryAdapter` does nothing here. SQLite and MongoDB override the method and create the real indexes.

### Conditional Requirements

`required_on` lets a field be required only for specific operations, perfect for `PATCH` operations where missing fields mean "do not update":

```crystal
PostSchema = Alumna::Schema.new
  .str("title", required_on: [:create, :update], min_length: 1)
  .str("body",  required_on: :create)
```
*(Note: If a field is `read_only: true`, Alumna is smart enough to never require it from the client during write operations, keeping your schema definitions clean.)*

### Strict Validation and Read-Only Fields

Alumna schemas are **strict by default**. If a client attempts to send extra fields that are not defined in the schema (e.g., a Mass Assignment attack), the validator will automatically reject the payload with an `"is not allowed"` error.

Reserved patch keys such as `"$unset"` are not schema fields. Strict validate skips them at the top of the payload. Nested `"$unset"` is still rejected. Unknown real fields still get `"is not allowed"` (HTTP **422**). Adapters that implement `$unset` (for example MongoDB) strip the key. MemoryAdapter does not implement `$unset`.

To opt out and allow unknown fields, initialize the schema with `Alumna::Schema.new(strict: false)`. Strictness settings automatically cascade to all nested hashes and arrays.

For fields that belong to your data model but should never be manipulated directly by the client (such as `id`, `created_at`, or `account_balance`), use `read_only: true`:

```crystal
AccountSchema = Alumna::Schema.new
  .str("id", read_only: true)
  .str("email", format: :email)
  .time("created_at", read_only: true)
  .time("updated_at", read_only: true)
```

When a field is marked as `read_only`:
1. If the client tries to send it during a write operation (`POST`, `PUT`, `PATCH`), the validator will reject it with an `"is read-only"` error.
2. The validator automatically waives the presence check (`required`) for these fields during write operations, so clients don't have to send them.
3. Because the block happens purely at the validation layer, your internal Rules and Database Adapters remain entirely free to safely compute and inject these values into `ctx.data` downstream!

Alumna includes a built-in `timestamp` rule to make handling dates completely effortless:

```crystal
app.use "/accounts", Alumna.memory(AccountSchema) {
  # 1. Reject any read-only fields if sent by the client
  before validate, on: :write
  
  # 2. Inject computed dates automatically
  before Alumna.timestamp("created_at"), on: :create
  before Alumna.timestamp("updated_at"), on: :write
}
```

### Pluggable Formats

Alumna ships with these built-in formats:

- `:email`, `:url`, `:uuid` - Crystal stdlib
- `:object_id` - 24 hex characters (`0-9`, `a-f`, `A-F`). Same rules as BSON ObjectId hex. The backend does not depend on bson.cr.

You can register your own formats once at application boot. They compile as Proc calls (no runtime hash lookups):

```crystal
Alumna::Formats.register("hex_color", "must be a valid hex color") do |v|
  v.matches?(/\A#(?:[0-9a-fA-F]{3}){1,2}\z/)
end

ProductSchema = Alumna::Schema.new
  .str("color", format: :hex_color)
```

---

## 3. Rules

A Rule is a single-responsibility pipeline hook. It is a `Proc` that takes a `RuleContext`. Returning `nil` continues the pipeline; returning a `ServiceError` halts it immediately.

```crystal
Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "Bearer my-secret" ? nil : Alumna::ServiceError.unauthorized
end
```

### Defining Rules

**For production code** – define a reusable constant, ideally in its own file:

```crystal
# src/rules/authenticate.cr
Authenticate = Alumna::Rule.new do |ctx|
  ctx.headers["authorization"]? ? nil : Alumna::ServiceError.unauthorized
end
```

**For prototypes or one-liners** – use the block form directly:

```crystal
before on: :write do |ctx|
  ctx.headers["authorization"]? ? nil : Alumna::ServiceError.unauthorized
end
```

Both compile to the same `Proc`. The block form runs once at boot with the service as its context.

### Execution Order & Hooks

Rules can be attached to the Application (global) or a specific Service. They are hooked into four phases:

```crystal
before       rule, on: :write   # runs before the service method
after        rule, on: :all     # runs after success (also on a cache hit)
after_commit rule, on: :mutate  # after the after phase, only if the method ran
error        rule               # runs if an error occurs anywhere
```

**Pipeline Execution Sequence:**
1. `app.before` rules
2. `service.before` rules
3. **service method** (`find`, `get`, etc.) - *skipped if a before-rule sets `ctx.result`*
4. `service.after` rules
5. `app.after` rules
6. `service.after_commit` rules — *only if the service method ran*
7. `app.after_commit` rules

If *any* rule or method returns a `ServiceError`, the pipeline jumps immediately to the error phase:
8. `service.error` rules
9. `app.error` rules

After-rules always run when there is no error, even if a before-rule short-circuited the service method. After-commit rules do not run on that shortcut. They also do not run if before, the method, or after went to the error phase. A successful `remove` (nil result, HTTP 204) still runs after-commit, because the method ran.

Error-rules always run when there is an error, even if it occurred in a before-rule. This makes logging, metrics, and response headers reliable for both success and failure paths.

### After commit

`after_commit` uses the same `Rule` type as `after`. Register it on App or Service. Use it for work that must not run on a cache hit. For example, publish after a write.

```crystal
app.after_commit on: :mutate do |ctx|
  # The service method already returned. Typical adapters autocommit in the method.
  # Publish to NATS here. See alumna-nats examples/websocket_fanout.cr.
  nil
end
```

**When it runs**

- After a successful `after` pipeline.
- Only if the service method ran (`Service#call_method`).
- A successful `remove` (nil result, HTTP 204) still runs it.
- A cache hit or a before-rule that set `ctx.result` skips it. `after` still runs.
- It does not run if before, the method, or after went to the error phase.
- Order is service then app.
- It runs for every `ctx.provider` (`rest`, `websocket`, `local`, `internal`).
- An `after_commit` rule may call `ctx.call`. Nested dispatch has its own `after_commit`.

**Errors after a durable write**

If an `after_commit` rule returns `ServiceError` or raises an uncaught `Exception`, `dispatch` runs the error pipeline. The client sees an error. The adapter write already completed. Alumna does not roll it back.

**Mongo `#transaction`**

There is no request transaction around `dispatch`. Official MongoDB `MongoAdapter#transaction` wraps adapter CRUD on that fiber, not `App#dispatch`. If you open `#transaction` and then call `dispatch` or `ctx.call` on the same fiber, `after` and `after_commit` still run before that block commits. In that case, publish after the block.

Cache fill, write-through, and the logger stay on `before` and `after`. Do not register those built-in rules on `after_commit`.

> **Note:** `options` HTTP calls (CORS preflights) are excluded from default `:all` scopes. To run a rule on an OPTIONS request, you must explicitly pass `on: :options`.

> **Strict Compilation:** For maximum performance and thread-safety, Alumna compiles and strictly freezes all rule pipelines the moment you call `app.listen`. Attempting to register a rule after the server boots will intentionally raise an Exception to prevent silent failures.

### Targeting Methods with `on:`

**`on:` controls which service methods run the rule.** It accepts:

- a `ServiceMethod` enum: `on: Alumna::ServiceMethod::Find`
- a symbol: `on: :create`, `on: :patch`
- an array: `on: [:find, :get]`
- a shorthand:
  - `:read`   → `find`, `get`
  - `:write`  → `create`, `update`, `patch` (not `remove`)
  - `:mutate` → `create`, `update`, `patch`, `remove`
  - `:all`    → all methods *except* `options`
- omit `on:` → same as `:all`

Use `on: :mutate` for `after_commit` when the rule must run on create, update, patch, and remove. `:write` does not include `remove`.

`options` is excluded by design since it's reserved for CORS preflights. If you need a rule to run on preflights, be explicit:

```crystal
before Alumna.cors(origins: ["*"]), on: :options
```

### The Rule Context

| Field | Description |
|---|---|
| `ctx.app` / `ctx.service` | Read-only references to the App and Service |
| `ctx.method` | The current enum method (`Find`, `Create`, etc.) |
| `ctx.http_method` | The raw HTTP verb (`GET`, `POST`, etc.) |
| `ctx.remote_ip` | Client IP (supports trusted proxy chains) |
| `ctx.provider` | **Read-Only** The request source: `"rest"` (TCP/HTTP), `"local"` (Unix socket), `"websocket"`, or `"internal"` (via `ctx.call`). |
| `ctx.id` | **Read-Only** URL ID of the targeted resource. |
| `ctx.params` / `ctx.headers`| Zero-allocation views of the request |
| `ctx.data` | The parsed request body |
| `ctx.result` | Response payload (set this to skip the service method) |
| `ctx.error` | Captured `ServiceError`, available in the error phase |
| `ctx.store` | A `Hash` scratch space to share data between rules |
| `ctx.http` | Object (`HttpOverrides`) to set `status`, `headers`, or `location` redirects |

> **Security Lock:** Foundational structural fields like `ctx.provider` and `ctx.id` are compiler-enforced read-only getters. They cannot be spoofed or accidentally mutated mid-flight by downstream rules.

### Headers, Params, and Views

`ctx.headers` and `ctx.params` are zero-allocation views. Writes go to an in-memory overlay so the original `HTTP::Request` is never mutated, but downstream rules instantly see the changes:

```crystal
ctx.headers["x-request-id"] = Random::Secure.hex(8)
ctx.params["locale"] = "en" unless ctx.params["locale"]?
```

- **HeadersView** – case-insensitive (`ctx.headers["authorization"]?` works for any casing), implements `Enumerable({String, String})`
- **ParamsView** – same API for query parameters, without case folding

The overlay is visible to all downstream rules and to the service, but it is not automatically reflected in the HTTP response – copy values to `ctx.http.headers` if you need to send them back.

### Sharing State with `ctx.store`

`ctx.store` is a per-request scratchpad used to pass data between rules and services (e.g., passing an authenticated `User` from an auth rule to your database adapter).

It natively accepts standard JSON-like primitives (Strings, Integers, Floats, Booleans, Times, Bytes, Hashes, Arrays). To store your own custom classes or structs, you must explicitly mark them by including `Alumna::Storeable`:

```crystal
class User
  include Alumna::Storeable
  
  getter id : Int32
  def initialize(@id); end
end

Authenticate = Alumna::Rule.new do |ctx|
  # Store the custom object safely
  ctx.store["user"] = User.new(42)
  nil
end
```

Downstream rules or services can then retrieve and cast it safely using standard Crystal semantics: `user = ctx.store["user"].as(User)`.

> **Tip:** While `Alumna::Storeable` works perfectly with both `class` and `struct`, prefer using `class` for very large data structures. Because `ctx.store` uses a mixed union type under the hood, massive structs will artificially inflate the memory footprint of the hash buffer.

---

## 4. Built-in Rules

Alumna ships with zero-dependency rules for common production needs:

### Validation

```crystal
before Alumna.validate(UserSchema), on: :write

# Or using the shorter helper inside a service:
before validate, on: :write
```

Returns a `422 Unprocessable Entity` with per-field details when validation fails. It automatically respects `required_on`.

`Alumna.validate(schema)` is a zero-magic shortcut. It is equivalent to:

```crystal
Alumna::Rule.new do |ctx|
  errors = schema.validate(ctx.data, ctx.method)
  next nil if errors.empty?
  details = errors.to_h { |e| {e.field, e.message} }
  Alumna::ServiceError.unprocessable("Validation failed", details)
end
```

When you need custom messages or transformations, call the schema directly inside your own rule:

```crystal
errors = UserSchema.validate(ctx.data, ctx.method)
```

### Timestamp

```crystal
before Alumna.timestamp("created_at"), on: :create
before Alumna.timestamp("updated_at"), on: :write
```

- Injects current `Time.utc` into specified field(s) of `ctx.data`.
- Can be paired with `read_only: true` on the field during schema definition, securing it to be only manipulated by the backend, not the client.
- Accepts multiple fields at once: `Alumna.timestamp("created_at", "updated_at")`.

### CORS

```crystal
before Alumna.cors(origins: ["https://app.example.com"])

# for preflights – OPTIONS is opt-in by design
before Alumna.cors(origins: ["https://app.example.com"]), on: :options
```

- Sets `Access-Control-Allow-Origin`, `Vary: Origin`, and credentials when enabled.
- Handles real preflights (`OPTIONS` + `Access-Control-Request-Method`) with a 204.
- `origins: ["*"]` is allowed for public APIs, but using it with `credentials: true` raises `ArgumentError` at boot – per the Fetch spec, wildcard cannot be used with credentials.
- **Convention:** global `before` rules do *not* run on `OPTIONS` unless you explicitly include `on: :options`. This prevents authentication or validation from blocking CORS preflights.

### Logger

```crystal
before Alumna.logger
after  Alumna.logger
```

Logs in combined format using a monotonic clock to measure request duration correctly:
```
5.5.5.5 "GET /users/123" 200 2.3ms
```
- Uses `ctx.remote_ip`, `ctx.http_method`, and `ctx.store` to correlate before/after phases.
- Works with any `IO` – pass `File.open("access.log", "a")` for file logging.

### Rate Limiter

The simplest form is one line. One hundred requests per minute, counted by client IP:

```crystal
app.before Alumna.rate_limit(limit: 100, window_seconds: 60)
```

Each request ticks a counter. Under the limit, the request continues and the response includes `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset`. Over the limit, Alumna returns `429 Too Many Requests`. CORS `OPTIONS` preflights are skipped so they do not consume the budget.

#### Count by something other than IP

The default key is `ctx.remote_ip`. If you would rather count by user, or mix both, pass `key:`:

```crystal
app.before Alumna.rate_limit(
  limit: 20,
  window_seconds: 60,
  key: ->(ctx : Alumna::RuleContext) {
    ctx.store["user_id"]?.as?(String) || ctx.remote_ip
  },
)
```

#### Share a store

That still uses an in-memory store local to this process. When two rules should share the same counters, build the store once and pass it in. `window_seconds` only applies when `store:` is omitted; here the window lives on the store:

```crystal
store = Alumna::MemoryRateLimitStore.new(60.seconds)
app.before Alumna.rate_limit(limit: 100, store: store)
app.before Alumna.rate_limit(limit: 10, store: store, key: ->(ctx : Alumna::RuleContext) { ctx.path })
```

#### Redis

Several processes cannot share that memory store. Give them Redis from [`alumna-redis`](https://github.com/alumna/redis) and they share the same counters:

```crystal
require "alumna-redis"

redis = Alumna::Redis.new(URI.parse(ENV["REDIS_URL"]))
app.before Alumna.rate_limit(limit: 100, store: redis.rate_limit_store(60.seconds))
```

The memory store drops expired windows as requests come in. There is no background fiber. Expiry uses a monotonic clock so NTP jumps do not stretch the window; `X-RateLimit-Reset` is still wall-clock time for the client.

### Cache

You attach a rule to a service. That rule talks to a store. You keep thinking in records; the rule writes the data for you (JSON into the store).

`MemoryCache` is one process. Several processes use Redis from [`alumna-redis`](https://github.com/alumna/redis). The rule is the same.

Start with one service:

```crystal
cache = Alumna::MemoryCache.new
cache_rule = Alumna.cache(cache, ttl: 30.seconds)

app.use "/posts", Alumna.memory(PostSchema) {
  before cache_rule, on: :read
  after cache_rule
}
```

`before` on `:read` covers `get` and `find`. If the data is already in the store, the rule sets `ctx.result` and the adapter never runs. `after` keeps the store in sync: it writes on create/update/patch, deletes on remove, and fills a miss.

#### Get

Get is one record, keyed by path and id (`alumna:get:/posts:12`). Create puts it in the cache immediately, so the next GET does not touch the adapter:

```
POST   /posts           write the new id into the cache
GET    /posts/12        hit (adapter skipped)
PATCH  /posts/12        write the new body into the cache
GET    /posts/12        hit with the new body
DELETE /posts/12        delete the key
GET    /posts/12        miss → adapter 404
```

If GET misses but the row exists, the adapter runs, then the rule stores the result with `set_nx`. That will not overwrite a key a concurrent write just saved.

#### Find

Find is a list, and lists are trickier. `GET /posts?status=draft` is not `GET /posts?status=published`. The rule hashes the query (filters, `$limit`, `$skip`, `$sort`, `$select`) so each distinct list has its own key.

A POST would still make those lists stale if the key were only the hash. So the rule also keeps a generation per path (`alumna:fgen:/posts`). Every create, update, patch, and remove increments it. Find keys include that number:

`alumna:find:{generation}:/posts:{query-hash}`

After a write, new finds use the new generation. Old list keys sit until `ttl` ends. The rule never scans the store to delete them.

`ttl` must be greater than 0. It is how long get keys and find lists live after a write. The generation key has no TTL on purpose: if it disappeared while old `find:0:…` keys were still around, those stale lists could look valid again.

#### Internal calls

By default `skip_providers:` is `["internal"]`. A `ctx.call` get or find skips the cache so a later step in the same request can see a fresh row. Internal writes still update get keys and bump the find generation.

#### Redis

Same attach on Redis (`before` on `:read`, `after`):

```crystal
require "alumna-redis"

redis = Alumna::Redis.new(URI.parse(ENV["REDIS_URL"]))
rule = Alumna.cache(redis.cache, ttl: 30.seconds)
```

Processes that share Redis share get results. They share find only if they also share the document store (two in-memory adapters each have their own rows).

The store hands you a copy of the data. Changing that copy does not change the store; call `set` if you want to persist. `MemoryCache` expires on a monotonic clock and drops stale rows on `get`. No background fiber.

### Session

The browser cookie is only an id. The data lives in a store. Start with memory, one process, login and logout:

```crystal
store = Alumna::MemorySessionStore.new(ttl: 24.hours)
sessions = Alumna::Session.new(store, secure: true)
app.before sessions.rule
```

In login, `start` writes the data and sets the cookie. In logout, `stop` deletes both. You can give one session a shorter life than the store default:

```crystal
sessions.start(ctx, Alumna.hash(user_id: id))
sessions.start(ctx, Alumna.hash(user_id: id), ttl: 8.hours)
sessions.stop(ctx)
```

No cookie → `401` `"Missing session"`. Unknown or expired id → `401` `"Unauthorized"`. The deadline is set on `start` (or `set`) and does not move on each request.

#### Cookie flags

Keep **one** `Session` object for the rule and for `start` / `stop`, so the cookie name and flags stay in sync. Defaults are `alumna.sid`, `HttpOnly`, `SameSite=Lax`, `Path=/`. Set `secure: true` on HTTPS. `same_site: :none` requires `secure: true`.

If you only need the before-rule and will call `Alumna::Session.start(ctx, store, data)` yourself, `Alumna.session(store)` is enough. Prefer the instance as soon as you set `cookie`, `secure`, or `same_site`.

#### Rotate

`rotate` deletes the old id and starts a new one — useful after login or a privilege change:

```crystal
sessions.rotate(ctx, Alumna.hash(user_id: id, role: "admin"))
```

`internal` and `local` are skipped, as is `OPTIONS`. After HTTP has loaded the session, `ctx.call` does not need the cookie again.

#### Redis

Several processes share a store the same way as cache and rate limit:

```crystal
require "alumna-redis"

redis = Alumna::Redis.new(URI.parse(ENV["REDIS_URL"]))
sessions = Alumna::Session.new(redis.session_store(ttl: 24.hours), secure: true)
app.before sessions.rule
```

`get` / `set` copy the top-level hash. Mutate it, then `set` (or `start`) to persist. That matches a remote store.

### JWT

HS256 verification. No JWT shard. Crystal 1.21 has HMAC in stdlib and no RSA key type, so RS256 is not in this release.

```crystal
secret = ENV["JWT_SECRET"]
app.before Alumna.jwt(secret)

# In login:
token = Alumna::JWT.encode(
  Alumna.hash(sub: id, exp: (Time.utc + 1.hour).to_unix),
  secret
)
```

- Missing header → `401` `"Missing token"`. Expired `exp` → `401` `"Token expired"`. Other failures → `401` `"Unauthorized"`.
- Default skip of `internal` and `local`. Skips `OPTIONS`.
- Optional `iss`, `aud`, and `leeway` on `Alumna.jwt`.
- `exp` / `nbf` / `iat` are Unix seconds (`Int64`). Use `Time.utc.to_unix`. Do not use `Time.instant`.
- Rejects `alg` `none` and any algorithm that is not HS256.
- Empty secret is `ArgumentError` at boot.

---

## 5. Server Configuration & Multi-threading

You boot your application by calling `app.listen`. By default, it binds to `127.0.0.1` on port `3000`. 

```crystal
app.listen(
  port: 3000, 
  host: "0.0.0.0",
  unix_socket: nil,
  trusted_proxies: ["10.0.0.0/8"],
  workers: 4,
  shutdown_timeout: 10.seconds
)
```

### Multi-threading and Workers

Alumna is thread-safe. By default, Crystal programs run on a single thread. To take advantage of modern multi-core processors, compile your application with the multithreading flags:

```bash
crystal build src/main.cr --release -Dpreview_mt -Dexecution_context
```

When compiled with these flags, Alumna will automatically configure the Fiber execution pool. You can explicitly set the number of threads via the `workers: N` argument in `app.listen`. If omitted, it gracefully defaults to your machine's logical CPU core count. 

### Unix Sockets & Local Providers

Alumna can serve HTTP traffic over standard TCP ports and local Unix sockets, either simultaneously or exclusively.

```crystal
# Listen on both TCP and a Unix socket
app.listen(3000, unix_socket: "/tmp/airsailer.sock")

# Listen exclusively on a Unix socket
app.listen(port: nil, unix_socket: "/tmp/airsailer.sock")
```

When a request arrives via the Unix socket, Alumna automatically detects it and sets `ctx.provider` to `"local"`. This makes it trivial to safely bypass strict authentication rules for background jobs or local CLI tools running as root on the same machine:

```crystal
Authenticate = Alumna::Rule.new do |ctx|
  # Bypass JWT checks for internal calls and local system CLI tools
  next nil if ctx.provider == "local" || ctx.provider == "internal"
  
  # ... normal JWT authentication logic ...
end
```

### WebSockets

The same HTTP server accepts `Upgrade: websocket`. `ctx.provider` is `"websocket"`. Handshake headers (Cookie, Authorization) are copied onto every frame. One `ctx.store` Hash lasts for the life of the socket.

JSON frames use the same services as REST:

```json
{"id":"1","method":"find","path":"/posts","params":{"$limit":10}}
{"id":"2","method":"get","path":"/posts","resource_id":"12"}
{"id":"3","method":"create","path":"/posts","data":{"title":"Hi"}}
```

`method` is `find`, `get`, `create`, `update`, `patch`, or `remove`. The reply has the same `id` and either `result` or `error` (`message`, `status`, optional `details`).

`App#connections` is `MemoryConnections`. Each socket has a `connection_id` in `ctx.store`. Use `send(id, payload)` for one socket. Use `watch` / `unwatch` / `send_topic` for a local topic. Delivery is this process only. Cross-process fan-out uses [Alumna NATS](https://github.com/alumna/nats) in the application. See `examples/websocket_fanout.cr` in that shard. Backend does not import NATS.

The frame size cap is `app.max_body_size` (default 1 MiB). An oversize frame returns status 413.

### Graceful Shutdown

Alumna safely traps `SIGINT` (Ctrl+C) and `SIGTERM`. When a shutdown signal is received, the server immediately stops accepting new connections but allows active HTTP requests to finish processing. Open WebSockets are closed first. They are not counted as active HTTP requests.

You can configure the maximum wait time using `shutdown_timeout` (defaults to 10 seconds). Once the timeout is reached, the server force-quits to prevent hanging indefinitely.

### Trusted Proxies

When Alumna runs behind Nginx, HAProxy, Cloudflare, or a Load Balancer, `ctx.remote_ip` must be correctly derived from proxy headers (`Forwarded`, `X-Forwarded-For`, `X-Real-IP`). 

- `trusted_proxies: nil` (default) – Never trust proxy headers.
- `trusted_proxies: true` – Trust headers from *any* client (useful for local dev).
- `trusted_proxies: ["10.0.0.0/8"]` – Trust headers only when the immediate peer IP matches the CIDR arrays. Supports bit-level matching for IPv4 and IPv6.

---

## Developer Experience

Alumna provides helpers to make writing rules and tests easier. We also recommend aliasing `Alumna::AnyData` at the top of your app:

```crystal
alias AnyData = Alumna::AnyData
```

### Fluid Service Errors
When you return a validation or bad request error, you can pass details as keyword arguments. Alumna casts them:

```crystal
# Instead of: Alumna::ServiceError.unprocessable("Invalid", {"age" => 18.as(AnyData)})
Alumna::ServiceError.unprocessable("Invalid", age: 18, email: "required")
```

### The `Alumna.hash` and `.to_any` helpers
When passing data to `ctx.call` or mutating arrays, use `Alumna.hash` and `.to_any` to avoid compiler generics friction:

```crystal
# Instead of: {"role" => "admin".as(AnyData)} of String => AnyData
# Also `ctx.call` resolves dynamic paths automatically. It is not necessary to split the path and the ID.
ctx.call("/users/123", :patch, data: Alumna.hash(role: "admin"))

# Instead of: ["a", "b"].map(&.as(AnyData))
ctx.data["tags"] = ["a", "b"].to_any
```

### Safe Deep Fetching
When reading from `ctx.data` (which is a `Hash(String, AnyData)`), Alumna provides `dig_any?` and typed variants (`dig_str?`, `dig_int?`, `dig_bool?`, etc.) that gracefully handle nested structures using dot-notation:

```crystal
# Safely extracts the string, returning nil if any part of the path is missing or isn't a string.
user_status = ctx.data.dig_str?("user.status") || "pending"
```

---

## Full Example

```crystal
require "alumna"

UserSchema = Alumna::Schema.new
  .str("name",  min_length: 2, max_length: 100)
  .str("email", format: :email)
  .int("age")

PostSchema = Alumna::Schema.new
  .str("title", required_on: [:create, :update], min_length: 1, max_length: 200)
  .str("body",  required_on: [:create, :update], min_length: 1)

Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "Bearer my-secret" ? nil : Alumna::ServiceError.unauthorized
end

app = Alumna::App.new

# Global app configurations
app.before Alumna.logger
app.after  Alumna.logger

app.use "/users", Alumna.memory(UserSchema) {
  before Authenticate
  before validate, on: :write
}

app.use "/posts", Alumna.memory(PostSchema) {
  before Authenticate
  before validate, on: :write
}

app.listen(3000)
```

---

## Serialization

Alumna supports JSON (default) and MessagePack out of the box. Format is negotiated dynamically per request using standard HTTP headers (`Content-Type` / `Accept`).

Under the hood, Alumna uses custom-built, zero-allocation stream parsers (`JSON::PullParser` and MessagePack's unbuffered lexer). This bypasses heavy intermediate wrapper types like `JSON::Any`, streaming payloads directly into Alumna's strict `AnyData` memory layout. `Time` objects are natively encoded and decoded as ISO8601 strings in JSON, and `Bytes` flow safely through both formats.

If you need a new serialization format (e.g. XML), simply implement `Alumna::Http::Serializer` and override the `encode` and `decode` methods.

---

## Testing

Alumna includes a built-in testing toolkit (`Alumna::Testing`) designed to make unit and integration tests incredibly fast and boilerplate-free. It bypasses network sockets entirely while running through the exact same router and orchestrator logic used in production.

### Testing Rules

Test individual rules in isolation without spinning up mock services. 

```crystal
require "alumna/testing" 

describe "Authenticate Rule" do
  it "blocks unauthorized requests" do
    result = Alumna::Testing.run_rule(Authenticate, headers: {"Authorization" => "wrong"})
    result.error.try(&.status).should eq(401)
  end
end
```

### Testing Applications

Use `AppClient` to test full request lifecycles instantly in memory:

```crystal
describe "User API" do
  app = Alumna::App.new
  app.use("/users", UserService.new)
  
  client = Alumna::Testing::AppClient.new(app)
  client.default_headers["Authorization"] = "Bearer my-secret"

  it "creates a user" do
    res = client.post("/users", body: %({"name": "Alice"}))
    res.status.should eq(201)
    res.json_hash["name"].as(String).should eq("Alice")
  end
end
```

### Testing WebSockets

Use `SocketClient` to run JSON frames through `App#dispatch` in memory. No `listen`.

```crystal
require "alumna/testing"

app = Alumna::App.new
app.use("/posts", Alumna.memory)
client = Alumna::Testing::SocketClient.new(app)
reply = client.call("create", "/posts", data: Alumna.hash(title: "Hi"))
reply["result"].as(Hash)["title"].should eq("Hi")
client.close
```

### Testing Adapters

`Alumna::Testing::AdapterSuite.run` runs the same CRUD, query, and concurrency specs that `MemoryAdapter` uses. The factory block runs inside every example. Yield a fresh adapter each time (empty table or collection).

```crystal
# Integer string ids ("1", "2", ...). This is the default. Use it for SQLite and MemoryAdapter.
Alumna::Testing::AdapterSuite.run("MyAdapter") { MyAdapter.new(schema) }

# Opaque string ids. Does not require ids to be integers.
Alumna::Testing::AdapterSuite.run("MyAdapter", expect_incremental_ids: false) { MyAdapter.new(schema) }

# Mixed-type $sort. Default :sql matches SQLite and MemoryAdapter ([2, "10", [1]]).
# Pass :bson for MongoDB native order (arrays by min element: [[1], 2, "10"]).
Alumna::Testing::AdapterSuite.run("MyAdapter", expect_incremental_ids: false, mixed_sort: :bson) { MyAdapter.new(schema) }
```

When `expect_incremental_ids` is `false`:
- `create` must return a non-empty String `id` and ignore a client-supplied `id`.
- Later `get` / `update` / `patch` / `remove` use that returned id.
- Concurrent creates must return unique ids. The suite does not parse them as integers.

`mixed_sort` only changes the mixed `metadata` `$sort` example. Same-type sorts stay the same.

---

## Roadmap

Alumna is prioritized for high-availability and real-time distributed platforms. The official MongoDB adapter is available at [`alumna/mongodb`](https://github.com/alumna/mongodb). Session and JWT rules ship in this version. Cache and `RateLimitStore` ports landed in v0.8.0. The Redis shard has `RedisCache`, `RedisSessionStore`, and `RedisRateLimitStore`. Native WebSockets landed in v0.9.0. The `after_commit` hook is in this tree. Cross-process WebSocket fan-out is application composition with [Alumna NATS](https://github.com/alumna/nats).

- **v0.10 - Event Bus & NATS:** Official **NATS.io** shard. Horizontally scaled Alumna instances publish from `after_commit` and fan-out to WebSocket clients through local `Connections`. Backend does not import NATS. See [alumna/nats](https://github.com/alumna/nats) `examples/websocket_fanout.cr`.
- **v0.11+ - Relational Expansion:** Official adapters for **PostgreSQL** and **MySQL**, utilizing the zero-allocation streaming, schema-driven SQL injection defenses, and JSONB dot-notation mapping established by our SQLite adapter.

---

## Design Decisions and Trade-offs

**Why rules instead of middleware?** 
Middleware in most frameworks is a general-purpose mechanism with implicit ordering and no declared intent. A rule has an explicit phase (`before`, `after`, `after_commit`, or `error`), an explicit target (all methods or a named subset), and a contract that returns a typed result. The intent is visible directly from the registration site.

**Why no resolvers?** 
FeathersJS resolvers automatically transform the result payload based on context. Alumna omits them in favour of explicit `after` rules that transform `ctx.result` directly. This is slightly more code in trivial cases but significantly easier to debug.

**Why `ServiceResult` uses `AnyData` instead of `JSON::Any`?** 
Alumna defines its own recursive union:

```crystal
alias AnyData = Nil | Bool | Int64 | Float64 | String | Time | Bytes | Array(AnyData) | Hash(String, AnyData)
alias ServiceResult = Hash(String, AnyData) | Array(Hash(String, AnyData)) | Nil
```

This lets every layer – context, services, rules, and serializers – work with native Crystal values instead of a wrapper type. The responder can dispatch on the actual type, MessagePack serializes without unwrapping, and validation errors flow through as plain hashes. It removes the `JSON::Any` dependency from the core, makes the context format-agnostic, and gives the compiler full visibility into data shapes for better errors and zero-cost abstractions.

**Why is `ServiceError` a struct instead of an Exception?** 
In many frameworks, returning a `404 Not Found` or a `422 Unprocessable Entity` involves raising an exception. In Crystal, instantiating an `Exception` allocates a call stack (backtrace), which adds measurable overhead under high load. By making `ServiceError` a lightweight `struct` returned directly by rules and service methods as a union type, Alumna achieves zero-allocation error paths. Expected API control flow never triggers the exception unwinding machinery, keeping throughput extremely high while remaining completely type-safe.

`FieldDescriptor` on the other hand is a class because it contains nearly 20 fields. As a struct it would copy all fields onto the stack for every field validation. As a class, it pays just a one-time heap allocation at boot and uses lightweight 8-byte references to maximize CPU cache.

**Flat routing API decision**
Alumna enforces flat routing by design to maintain O(1) routing performance and a more efficient caching on both server-side and client-side. Nested relationships should be handled via query parameters (e.g., /posts?userId=123).

**Why Crystal?** 
Expressive syntax that lowers the barrier for developers coming from Ruby or TypeScript. Ahead-Of-Time (AOT) compilation and a single binary output eliminates runtime dependency management at deploy time. Performance that competes with Go and Rust without sacrificing readability.

**100% coverage strategy**
Alumna enforces 100% code coverage by design. This delivers immediate feedback on regressions in pull requests and gives developers the confidence to refactor, optimize, and introduce new features without fear of breaking existing behavior.

As foundational infrastructure, Alumna treats complete behavioral correctness as non-negotiable.

---

## Contributing

Alumna is in early development and contributions are very welcome! Please open an issue before starting significant work so we can align on direction.

```bash
git clone https://github.com/alumna/backend
cd alumna
shards install
crystal spec
```

---

## License

MIT
