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
    - [Writing a Custom Adapter](#writing-a-custom-adapter)
- [2. Schemas](#2-schemas)
    - [Nested Fields](#nested-fields-objects-and-arrays)
    - [Conditional Requirements](#conditional-requirements)
    - [Pluggable Formats](#pluggable-formats)
- [3. Rules](#3-rules)
    - [Defining Rules](#defining-rules)
    - [Execution Order & Hooks](#execution-order--hooks)
    - [Targeting Methods with `on:`](#targeting-methods-with-on)
    - [The Rule Context](#the-rule-context)
    - [Headers, Params, and Views](#headers-params-and-views)
- [4. Built-in Rules](#4-built-in-rules)
    - [Validation](#validation)
    - [CORS](#cors)
    - [Logger](#logger)
    - [Rate Limiter](#rate-limiter)
- [5. Server Configuration & Multi-threading](#5-server-configuration--multi-threading)
    - [Multi-threading and Workers](#multi-threading-and-workers)
    - [Graceful Shutdown](#graceful-shutdown)
    - [Trusted Proxies](#trusted-proxies)
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

Alumna inherits Crystal's performance characteristics: ahead-of-time compilation, a single self-contained binary, no runtime dependencies, and throughput that benchmarks consistently alongside Go and Rust—all with a syntax beautifully close to Ruby.

---

## Status

Alumna is in active early development. The following core pieces are complete and tested:

- ✅ HTTP layer with RESTful routing and content negotiation
- ✅ Rule pipeline with explicit `before`, `after`, and `error` phases
- ✅ Deep schema validation with path-tracing for nested arrays/objects
- ✅ Zero-allocation validation formats resolved at definition time
- ✅ In-memory adapter implementing the full service interface
- ✅ JSON and MessagePack serialization
- ✅ Rich `RuleContext` with safe, zero-allocation views for headers and params
- ✅ Advanced query parsing (`$limit`, `$skip`, `$sort`, `$select`, `$in`, `$gt`, etc.)
- ✅ Safe multi-threading and graceful server shutdown
- ✅ Cross-platform CI with full test coverage
- ✅ Path normalization and duplicate-route protection
- ✅ Strict request-body limits enforced on all IO entry points
- ✅ `provider` field on context distinguishing `"rest"` from future `"websocket"`

See the [Roadmap](#roadmap) for what is coming next.

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

*Crystal 1.19.1 or later is required.*

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

Alumna automatically parses URL query strings into a strongly-typed `ctx.query` object. It natively supports MongoDB/FeathersJS-style comparison operators and nested dot-notation.

```crystal
# GET /users?age[$gte]=18&status[$in]=active,pending&billing.plan=pro&$limit=10&$sort=age:-1

ctx.query.filters["age"]          # => [{op: Op::Gte, value: "18"}]
ctx.query.filters["status"]       # => [{op: Op::In, value: ["active", "pending"]}]
ctx.query.filters["billing.plan"] # => [{op: Op::Eq, value: "pro"}]
ctx.query.limit                   # => 10
ctx.query.sort                    # => [{"age", -1}]
```

**Supported operators:** `$eq` (default), `$ne`, `$gt`, `$gte`, `$lt`, `$lte`, `$in`, `$nin`.

The built-in `MemoryAdapter` implements all of these out of the box. When building custom database adapters, you simply read `ctx.query` to compile your SQL/NoSQL statements.

### Writing a Custom Adapter

To connect a real database, inherit from `Alumna::Service` and implement its six abstract methods. Each method receives the full `RuleContext` and returns a typed value.

```crystal
class PostgresUserService < Alumna::Service
  def initialize(@db : DB::Database)
    super(UserSchema)
    self.before(Authenticate)
  end

  def find(ctx : RuleContext) : Array(Hash(String, AnyData)) | ServiceError
    # query @db using ctx.query.filters, limit, skip, and sort
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

  def remove(ctx : RuleContext) : Bool | ServiceError
    # delete record at ctx.id, return true if deleted
    false
  end
end
```

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

**Supported field types:** `:str`, `:int`, `:float`, `:bool`, `:nullable`, `:hash`, `:array` (or `Alumna::FieldType::Str`, etc.).

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

### Conditional Requirements

`required_on` lets a field be required only for specific operations, perfect for `PATCH` operations:

```crystal
PostSchema = Alumna::Schema.new
  .str("title", required_on: [:create, :update], min_length: 1)
  .str("body",  required_on: :create)
```

### Pluggable Formats

Alumna ships with `:email`, `:url`, and `:uuid` backed by Crystal's stdlib. You can register your own formats once at application boot, which are directly compiled as Proc calls (no runtime hash lookups):

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

Rules can be attached to the Application (global) or a specific Service. They are hooked into three phases:

```crystal
before rule, on: :write  # runs before the service method
after  rule, on: :all    # runs after a successful service method
error  rule              # runs if an error occurs anywhere
```

**Pipeline Execution Sequence:**
1. `app.before` rules
2. `service.before` rules
3. **service method** (`find`, `get`, etc.) - *skipped if a before-rule sets `ctx.result`*
4. `service.after` rules
5. `app.after` rules

If *any* rule or method returns a `ServiceError`, the pipeline jumps immediately to the error phase:
6. `service.error` rules
7. `app.error` rules

After-rules always run when there is no error, even if a before-rule short-circuited the service method. Error-rules always run when there is an error, even if it occurred in a before-rule. This makes logging, metrics, and response headers reliable for both success and failure paths.

*Note: `options` HTTP calls (CORS preflights) are excluded from default `:all` scopes. To run a rule on an OPTIONS request, you must explicitly pass `on: :options`.*

### Targeting Methods with `on:`

**`on:` controls which service methods run the rule.** It accepts:

- a `ServiceMethod` enum: `on: Alumna::ServiceMethod::Find`
- a symbol: `on: :create`, `on: :patch`
- an array: `on: [:find, :get]`
- a shorthand:
  - `:read`  → `find`, `get`
  - `:write` → `create`, `update`, `patch`, `remove`
  - `:all`   → all methods *except* `options`
- omit `on:` → same as `:all`

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
| `ctx.provider` | Request source – `"rest"` today, `"websocket"` in future |
| `ctx.params` / `ctx.headers`| Zero-allocation views of the request |
| `ctx.id` / `ctx.data` | URL ID and parsed request body |
| `ctx.result` | Response payload (set this to skip the service method) |
| `ctx.error` | Captured `ServiceError`, available in the error phase |
| `ctx.store` | A `Hash` scratch space to share data between rules |
| `ctx.http` | Object (`HttpOverrides`) to set `status`, `headers`, or `location` redirects |

### Headers, Params, and Views

`ctx.headers` and `ctx.params` are zero-allocation views. Writes go to an in-memory overlay so the original `HTTP::Request` is never mutated, but downstream rules instantly see the changes:

```crystal
ctx.headers["x-request-id"] = Random::Secure.hex(8)
ctx.params["locale"] = "en" unless ctx.params["locale"]?
```

- **HeadersView** – case-insensitive (`ctx.headers["authorization"]?` works for any casing), implements `Enumerable({String, String})`
- **ParamsView** – same API for query parameters, without case folding

The overlay is visible to all downstream rules and to the service, but it is not automatically reflected in the HTTP response – copy values to `ctx.http.headers` if you need to send them back.

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

```crystal
before Alumna.rate_limit(limit: 100, window_seconds: 60)
```

- In-memory fixed-window limiter per key (defaults to client IP; override with `key: ->(ctx) { ... }`).
- Uses a monotonic clock for expiry, so limits stay accurate across system clock changes.
- Memory-bounded store: entries expire after their window and are pruned by an amortized in-request cleanup – no background fiber.
- Sets `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`.
- Returns `429 Too Many Requests` when exceeded.
- Skips `OPTIONS` requests automatically.

---

## 5. Server Configuration & Multi-threading

You boot your application by calling `app.listen`. By default, it binds to `127.0.0.1` on port `3000`. 

```crystal
app.listen(
  3000, 
  host: "0.0.0.0",
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

### Graceful Shutdown

Alumna safely traps `SIGINT` (Ctrl+C) and `SIGTERM`. When a shutdown signal is received, the server immediately stops accepting new connections but allows active requests to finish processing. 

You can configure the maximum wait time using `shutdown_timeout` (defaults to 10 seconds). Once the timeout is reached, the server force-quits to prevent hanging indefinitely.

### Trusted Proxies

When Alumna runs behind Nginx, HAProxy, Cloudflare, or a Load Balancer, `ctx.remote_ip` must be correctly derived from proxy headers (`Forwarded`, `X-Forwarded-For`, `X-Real-IP`). 

- `trusted_proxies: nil` (default) – Never trust proxy headers.
- `trusted_proxies: true` – Trust headers from *any* client (useful for local dev).
- `trusted_proxies: ["10.0.0.0/8"]` – Trust headers only when the immediate peer IP matches the CIDR arrays. Supports bit-level matching for IPv4 and IPv6.

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
    res.json["name"].as_s.should eq("Alice")
  end
end
```

Writing a custom database adapter? Use `Alumna::Testing::AdapterSuite.run("MyAdapter") { MyAdapter.new }` to instantly run dozens of compliance specs against your implementation!

---

## Roadmap

### v0.6 - Security and authentication
- JWT and session authentication helper rules.

### v0.7 - v0.8 Real Database Adapters
- **SQLite** adapter (using `crystal-sqlite3`).
- **MySQL** and **PostgreSQL** adapters (using `crystal-db`).
- Adapters will read the service schema to introspect column names and types automatically.

### v0.9 - Real-time events via WebSocket
- Emit service events automatically after successful mutations (`created`, `updated`, `patched`, `removed`).
- Allow clients to subscribe to specific service paths over a WebSocket connection.

### v0.10 - v0.11 Horizontal Scaling & Cache
- **Redis adapter** for caching.
- **NATS integration** for horizontal scaling. Stateless service instances will publish events to NATS subjects, enabling real-time WebSocket fan-out across multiple Alumna instances behind a load balancer.

---

## Design Decisions and Trade-offs

**Why rules instead of middleware?** 
Middleware in most frameworks is a general-purpose mechanism with implicit ordering and no declared intent. A rule has an explicit phase (`before`, `after`, or `error`), an explicit target (all methods or a named subset), and a contract that returns a typed result. The intent is visible directly from the registration site.

**Why no resolvers?** 
FeathersJS resolvers automatically transform the result payload based on context. Alumna omits them in favour of explicit `after` rules that transform `ctx.result` directly. This is slightly more code in trivial cases but significantly easier to debug.

**Why `ServiceResult` uses `AnyData` instead of `JSON::Any`?** 
Alumna defines its own recursive union:

```crystal
alias AnyData = Nil | Bool | Int64 | Float64 | String | Array(AnyData) | Hash(String, AnyData)
alias ServiceResult = Hash(String, AnyData) | Array(Hash(String, AnyData)) | Nil
```

This lets every layer – context, services, rules, and serializers – work with native Crystal values instead of a wrapper type. The responder can dispatch on the actual type, MessagePack serializes without unwrapping, and validation errors flow through as plain hashes. It removes the `JSON::Any` dependency from the core, makes the context format-agnostic, and gives the compiler full visibility into data shapes for better errors and zero-cost abstractions.

**Why is `ServiceError` a struct instead of an Exception?** 
In many frameworks, returning a `404 Not Found` or a `422 Unprocessable Entity` involves raising an exception. In Crystal, instantiating an `Exception` allocates a call stack (backtrace), which adds measurable overhead under high load. By making `ServiceError` a lightweight `struct` returned directly by rules and service methods as a union type, Alumna achieves zero-allocation error paths. Expected API control flow never triggers the exception unwinding machinery, keeping throughput extremely high while remaining completely type-safe.

**Why Crystal?** 
Expressive syntax that lowers the barrier for developers coming from Ruby or TypeScript. Ahead-Of-Time (AOT) compilation and a single binary output eliminates runtime dependency management at deploy time. Performance that competes with Go and Rust without sacrificing readability.

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
