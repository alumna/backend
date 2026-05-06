![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/alumna/backend/ci.yml) [![codecov](https://codecov.io/gh/alumna/backend/graph/badge.svg?token=GX1Z8DNR3W)](https://codecov.io/gh/alumna/backend) ![Dynamic YAML Badge](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Falumna%2Fbackend%2Frefs%2Fheads%2Fmaster%2Fshard.yml&query=version&prefix=v&label=version) ![GitHub License](https://img.shields.io/github/license/alumna/backend)

# Alumna

A minimalist, service-oriented backend framework for [Crystal](https://crystal-lang.org), inspired by the core architecture of [FeathersJS](https://feathersjs.com) and designed around three ideas: simplicity, explicitness, and performance.

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

# Built-in adapters
class MessageService < Alumna::MemoryAdapter
  def initialize
    super(MessageSchema)
    before Authenticate
    before Alumna.validate(MessageSchema), on: :write
  end
end

# Done
app = Alumna::App.new
app.use("/messages", MessageService.new)
app.listen(3000) # binds to 127.0.0.1:3000 by default
```

---

## Table of Contents
- [Backend can be simple](#backend-can-be-simple)
- [Philosophy](#philosophy)
- [Status](#status)
- [Installation](#installation)
- [Core concepts](#core-concepts)
    - [Schema](#schema)
        - [Pluggable formats](#pluggable-formats)
    - [Validation: Built-in validation rule](#validation-built-in-validation-rule)
    - [Validation: custom validator](#validation-custom-validator)
    - [Built-in rules](#built-in-rules)
- [Rules](#rules)
- [Headers, params, and client IP](#headers-params-and-client-ip)
- [Services](#services)
- [Example of global rules in an application](#example-of-global-rules-in-an-application)
- [Full example](#full-example)
- [Writing a custom adapter](#writing-a-custom-adapter)
- [Serialization](#serialization)
- [Roadmap](#roadmap)
- [Design decisions and trade-offs](#design-decisions-and-trade-offs)
- [Contributing](#contributing)
- [License](#license)

---

## Philosophy

Most backend frameworks ask you to learn their full architecture before you can write a single working endpoint. Alumna takes the opposite approach.

The entire model fits in your head at once:

- A **Service** exposes a standard set of methods (`find`, `get`, `create`, `update`, `patch`, `remove`, `options`) and is automatically mounted as a RESTful HTTP API at a given path. `options` is reserved for CORS preflights and has no business logic by default.
- A **Rule** is a single-responsibility function that receives a request context, applies one concern - authentication, validation, rate limiting, logging - and returns `nil` to continue or a `ServiceError` to stop the pipeline. Rules do not call each other; a flat orchestrator sequences them. Rules can be registered globally on the app or per-service.
- A **Schema** describes the shape of a service's data. It is used for input validation inside rules and as a structural hint for storage adapters.

There is no magic, no dependency injection container, no decorator metadata, no resolver chain. Every moving piece is visible and explicit. A developer new to the codebase can read a service definition and understand the full execution path in minutes.

Alumna inherits Crystal's performance characteristics: ahead-of-time compilation, a single self-contained binary, no runtime dependencies, and throughput that benchmarks consistently alongside Go and Rust - with a syntax closer to Ruby.

---

## Status

Alumna is in active early development. The following core pieces are complete and tested:

- ✅ HTTP layer with RESTful routing and content negotiation
- ✅ Rule pipeline with explicit before, after, and error phases
- ✅ Schema validation with pluggable formats resolved at definition time (`:email`, `:url`, `:uuid`, and custom)
- ✅ In-memory adapter implementing the full service interface
- ✅ JSON and MessagePack serialization
- ✅ Rich `RuleContext` with `store`, `remote_ip` (with trusted proxy support), `http_method`, `headers`, and `provider`
- ✅ Query parsing (`$limit`, `$skip`, `$sort`, `$select`) via `ctx.query`
- ✅ Path normalization and duplicate-route protection
- ✅ Strict request-body limits enforced on all IO entry points
- ✅ Cross-platform CI with full test coverage

Production-ready built-in rules:

- ✅ CORS
- ✅ request logging
- ✅ rate limiting (memory-bounded, monotonic clock)
- ✅ validation

See the [Roadmap](#roadmap) for what is coming next.

---

## Installation

Add Alumna to your `shard.yml`:

```yaml
dependencies:
  alumna:
    github: alumna/backend
```

Then run:

```bash
shards install
```

Require it in your project:

```crystal
require "alumna"
```

Crystal 1.19.1 or later is required.

---

## Core concepts

### Schema

A schema describes the fields a service works with. It is used by rules for input validation and by adapters to understand the record structure.

```crystal
# Type helpers - required is true by default
UserSchema = Alumna::Schema.new
  .str("name",  min_length: 2, max_length: 100)
  .str("email", format: :email)
  .int("age")
  .bool("admin", required: false) # only specify when field is optional

# More explicit with `field` helper
UserSchema = Alumna::Schema.new
  .field("name",  :str, min_length: 2, max_length: 100)
  .field("email", :str, format: :email)
  .field("age",   :int)
  .field("admin", :bool, required: false)
```

**Supported field types:** `:str`, `:int`, `:float`, `:bool`, `:nullable` (or `Alumna::FieldType::Str`, etc.)

**Supported formats:** `:email`, `:url`, `:uuid` - these are built-in and backed by Crystal's stdlib (`URI.parse`, `UUID.parse`). Formats are resolved once when the schema is defined, so validation is a direct Proc call with no hash lookups at runtime.

**Supported constraints:** `required`, `required_on`, `min_length`, `max_length`, `format`

`required_on` lets a field be required only for specific operations - perfect for PATCH:

```crystal
PostSchema = Alumna::Schema.new
  .str("title", required_on: [:create, :update], min_length: 1, max_length: 200)
  .str("body",  required_on: [:create, :update], min_length: 1)
```

#### Pluggable formats

Formats are not hard-coded. Alumna ships with `:email`, `:url`, and `:uuid`, but you can register your own once at application boot:

```crystal
Alumna::Formats.register("hex_color", "must be a valid hex color") do |v|
  v.matches?(/\A#(?:[0-9a-fA-F]{3}){1,2}\z/)
end

ProductSchema = Alumna::Schema.new
  .str("name")
  .str("color", format: :hex_color)
```

- Registration happens before schemas are built; the validator Proc is stored in the field descriptor
- Unknown formats raise `ArgumentError` at schema definition time (fail-fast)
- Built-in formats follow real-world behavior: UUIDs accept both hyphenated and compact forms, URLs accept surrounding whitespace and require `http` or `https`

**Required by default**

All fields are required unless you pass `required: false` or limit them with `required_on`. This matches Crystal's philosophy of failing fast - you opt out of validation, not into it.

| Declaration | Result |
|---|---|
| `.str("title")` | required on every method |
| `.str("title", required: false)` | optional on every method |
| `.str("title", required_on: [:create, :update])` | required only for create and update, optional for patch |

### Validation: Built-in validation rule

Most services validate the same way, so Alumna ships a helper that builds the rule for you:

```crystal
Alumna.validate(UserSchema)
```

It’s equivalent to:

```crystal
Alumna::Rule.new do |ctx|
  errors = UserSchema.validate(ctx.data, ctx.method)
  next nil if errors.empty?
  details = errors.to_h { |e| {e.field, e.message} }
  Alumna::ServiceError.unprocessable("Validation failed", details)
end
```

Because it receives `ctx.method`, it automatically respects `required_on: [:create, :update]`. Use it directly in your service:

```crystal
class UserService < Alumna::MemoryAdapter
  def initialize
    super(UserSchema)
    before Alumna.validate(UserSchema), on: :write
  end
end
```

You still keep full control - write your own rule when you need custom messages, transformations, or conditional validation. `Alumna.validate` is just a zero-magic shortcut for the 90% case.

### Validation: custom validator

Schemas are plain objects. When needed, inside your own rule, call `schema.validate(data, method)` to get back an `Array(Alumna::FieldError)`. Pass the current `ctx.method` so `required_on` is respected:

```crystal
errors = PostSchema.validate(ctx.data, ctx.method)
```

### Built-in rules

Alumna ships with four zero-dependency rules that cover the most common production needs. They live in `src/rule/builtin/` and are exposed as simple factory methods:

```crystal
Alumna.validate(schema)                    # schema validation
Alumna.cors(origins: ["*"])                # CORS headers
Alumna.logger(io = STDOUT)                 # request logging
Alumna.rate_limit(limit: 100, window_seconds: 60) # in-memory rate limiting
```

**1. Validation**
```crystal
before Alumna.validate(UserSchema), on: :write
```
Returns 422 with per-field details when validation fails. Respects `required_on`.

**2. CORS**
```crystal
# for normal requests
before Alumna.cors(origins: ["https://app.example.com"])
# for preflights — OPTIONS is opt-in by design
before Alumna.cors(origins: ["https://app.example.com"]), on: :options
```
- Sets `Access-Control-Allow-Origin`, `Vary: Origin`, and credentials when enabled
- Handles real preflights (`OPTIONS` + `Access-Control-Request-Method`) with 204
- `origins: ["*"]` is allowed for public APIs, but using it with `credentials: true` raises `ArgumentError` at boot — per the Fetch spec, wildcard cannot be used with credentials
- **Convention:** global `before` rules do *not* run on `OPTIONS` unless you explicitly include `on: :options`. This prevents authentication or validation from blocking CORS preflights, matching the HTTP spec.

**3. Logger**
```crystal
before Alumna.logger
after Alumna.logger
```
Logs in combined format using the monotonic clock:
```
5.5.5.5 "GET /users/123" 200 2.3ms
```
- Uses `ctx.remote_ip`, `ctx.http_method`, and `ctx.store` to correlate before/after phases
- Works with any `IO` - pass `File.open("access.log", "a")` for file logging

**4. Rate limiter**
```crystal
before Alumna.rate_limit(limit: 60, window_seconds: 60)
```
- In-memory fixed-window limiter per key (defaults to client IP; override with `key: ->(ctx) { ... }`)
- Uses a monotonic clock (`Time::Instant`) for expiry, so limits stay accurate across system clock changes
- Memory-bounded store: entries expire after their window and are pruned by an amortized in-request cleanup - no unbounded Hash growth, no background fiber
- Sets `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- Returns 429 when exceeded
- Skips `OPTIONS` requests automatically

All four are regular `Rule` objects - you can compose them with your own rules, limit them with `on:`, and test them with `RuleRunner` like any custom rule.

---

### Rules

A rule is a `Proc` that receives a `RuleContext` and returns a `nil` to continue and a `ServiceError` to stop. Rules are values, not classes - they are defined once and registered globally on the application or on individual services.

```crystal
# A rule that checks for a valid bearer token
Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "Bearer my-secret" ? nil : Alumna::ServiceError.unauthorized
end

# An after-rule that adds a response header
AddRequestId = Alumna::Rule.new do |ctx|
  ctx.http.headers["X-Request-ID"] = Random::Secure.hex(8)
  nil
end

# An error-rule that logs failures
LogError = Alumna::Rule.new do |ctx|
  Log.error { "Request failed: #{ctx.error.message}" } if ctx.error
  ctx.http.headers["X-Error-ID"] = Random::Secure.hex(4)
  nil
end
```

#### Two ways to register a rule

**For production code** - define a reusable constant, ideally in its own file:

```crystal
# src/rules/authenticate.cr
Authenticate = Alumna::Rule.new do |ctx|
  ctx.headers["authorization"]? ? nil : Alumna::ServiceError.unauthorized
end
```

**For prototypes or one-liners** - use the block form directly:

```crystal
before on: :write do |ctx|
  ctx.headers["authorization"]? ? nil : Alumna::ServiceError.unauthorized
end
```

Both compile to the same `Proc`. The block form provides convenience, while the constant form is more recommended because it keeps rules testable and encourages one-file-per-concern architecture.

**What is available on the context:**

| Field | Type | Description |
|---|---|---|
| `ctx.app` | `App` | The application instance |
| `ctx.service` | `Service` | The service handling this request |
| `ctx.path` | `String` | The service path, e.g. `"/users"` |
| `ctx.method` | `ServiceMethod` | `Find`, `Get`, `Create`, `Update`, `Patch`, `Remove` |
| `ctx.phase` | `RulePhase` | `Before`, `After`, or `Error` |
| `ctx.http_method` | `String` | Original HTTP verb (`GET`, `POST`, etc.) |
| `ctx.remote_ip` | `String` | Client IP address; when trusted proxies are configured, correctly extracted from `Forwarded`, `X-Forwarded-For`, or `X-Real-IP`, otherwise the direct socket address |
| `ctx.provider` | `String` | Transport that invoked the service (`"rest"` today, `"websocket"` in future) |
| `ctx.params` | `ParamsView` | Query string parameters; supports `[]`, `[]?`, `[]=` with an overlay that shadows the original request |
| `ctx.headers` | `HeadersView` | Request headers; case-insensitive reads, writes go to an overlay (does not mutate the incoming request) |
| `ctx.id` | `String?` | Record ID from the URL, if present |
| `ctx.data` | `Hash(String, AnyData)` | Parsed request body |
| `ctx.result` | `ServiceResult` | Response payload; set this in a before-rule to skip the service method (after-rules still run) |
| `ctx.error` | `ServiceError?` | Present when the pipeline is in the error phase |
| `ctx.store` | `Hash(String, AnyData)` | Per-request scratch space for sharing data between before/after rules |
| `ctx.http.status` | `Int32?` | Override the HTTP response status code |
| `ctx.http.headers` | `Hash(String, String)` | Add custom HTTP response headers |
| `ctx.http.location` | `String?` | Set to trigger an HTTP redirect |

> `ctx.method`, `ctx.path`, `ctx.app`, and `ctx.service` are read-only by design - rules transform data, not routing. Use `ctx.params`, `ctx.data`, `ctx.result`, and `ctx.error` for all mutations.

> When you call `app.use`, Alumna pre-compiles the before/after pipelines for each method, so dispatch is a simple array walk with zero allocations.

### Headers, params, and client IP

`ctx.headers` and `ctx.params` are not plain hashes. They are zero-allocation views:

- **HeadersView** – case-insensitive (`ctx.headers["authorization"]?` works for any casing), implements `Enumerable({String, String})`, and supports `[]`, `[]?`, `[]=`, and `each`. Writes go to an in-memory overlay; the original `HTTP::Request` is never mutated.
- **ParamsView** – same API for query parameters, without case folding.

This lets rules enrich the request safely:

```crystal
ctx.headers["x-request-id"] = Random::Secure.hex(8)
ctx.params["locale"] = "en" unless ctx.params["locale"]?
```

The overlay is visible to all downstream rules and to the service, but it is not automatically reflected in the HTTP response - copy values to `ctx.http.headers` if you need to send them back.

**Listening and network binding**

By default `app.listen` binds only to the loopback interface for safety:

```crystal
app.listen(3000) # http://127.0.0.1:3000
```

To expose the server publicly, pass an explicit host:

```crystal
app.listen(3000, host: "0.0.0.0")
```

**Trusted proxies**

When Alumna runs behind Nginx, HAProxy, Cloudflare, or a load balancer, `ctx.remote_ip` must be derived from proxy headers. Configure trusted proxies when you start the server:

```crystal
app = Alumna::App.new
app.use("/messages", MessageService.new)

# Production behind a private load balancer
app.listen(3000,
  host: "0.0.0.0",
  trusted_proxies: ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
)

# Local development only – trust all hops
# app.listen(3000, host: "127.0.0.1", trusted_proxies: true)
```

- `host: "127.0.0.1"` (default) – binds to localhost only; use "0.0.0.0" or "::" for all interfaces
- `trusted_proxies: nil` (default) – never trust proxy headers
- `true` – trust `Forwarded`, `X-Forwarded-For`, and `X-Real-IP` from any client
- `Array(String)` – trust only when the immediate peer IP matches a CIDR; IPv4 and IPv6 are fully supported

Parsing follows the standard order: `Forwarded` → `X-Forwarded-For` → `X-Real-IP`. The implementation uses `IPCidr` with bit-level matching, no regexes on the hot path, and is covered by dedicated specs.

**Signalling outcomes:**

```crystal
nil                             # proceed to the next rule or service method
ServiceError.unauthorized       # halt the pipeline and return an error response
ServiceError.bad_request("...") # halt with a custom error
```

**Available `ServiceError` constructors:**

```crystal
ServiceError.bad_request("message", details)   # 400
ServiceError.unauthorized("message")           # 401
ServiceError.forbidden("message")              # 403
ServiceError.not_found("message")              # 404
ServiceError.unprocessable("message", details) # 422
ServiceError.internal("message")               # 500
```

`details` is a `Hash(String, String)` for per-field error messages.

---

### Services

A service inherits from `Alumna::MemoryAdapter` (or from `Alumna::Service` directly) and registers its rules in the constructor.

```crystal
class UserService < Alumna::MemoryAdapter
  def initialize
    super(UserSchema)
    before Authenticate
    before Alumna.validate(UserSchema), on: :write
    after AddRequestId
    error LogError
  end
end
```

#### Registering rules

Rules are attached in a service (or app) constructor with three methods:

```crystal
before rule, on: ...
after  rule, on: ...
error  rule, on: ...
```

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

**HTTP mapping:**

| Service method | HTTP verb | Path |
|---|---|---|
| `find` | `GET` | `/users` |
| `get` | `GET` | `/users/:id` |
| `create` | `POST` | `/users` |
| `update` | `PUT` | `/users/:id` |
| `patch` | `PATCH` | `/users/:id` |
| `remove` | `DELETE` | `/users/:id` |
| `options` | `OPTIONS` | `/users` or `/users/:id` |


**Execution order:**

When a request arrives, rules run in this exact sequence:

1. `app.before` rules
2. `service.before` rules
3. service method (`find`, `get`, etc.) - skipped if a before-rule set `ctx.result`
4. `service.after` rules
5. `app.after` rules

If any rule returns a `ServiceError`, the pipeline jumps immediately to error rules:

6. `service.error` rules
7. `app.error` rules

After-rules always run when there is no error, even if a before-rule short-circuited the service method. Error-rules always run when there is an error, even if it occurred in a before-rule. This makes logging, metrics, and response headers reliable for both success and failure paths.

---

### Example of global rules in an application

```crystal
app = Alumna::App.new

# Global rules run for every service
app.before CORS
app.before RateLimit
app.after Logger
app.error LogError

app.use("/users", UserService.new)
app.listen(3000) # localhost only
```

---

## Full example

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

class UserService < Alumna::MemoryAdapter
  def initialize
    super(UserSchema)
    before Authenticate
    before Alumna.validate(UserSchema), on: :write
  end
end

class PostService < Alumna::MemoryAdapter
  def initialize
    super(PostSchema)
    before Authenticate
    before Alumna.validate(PostSchema), on: :write

  end
end

app = Alumna::App.new
app.use("/users", UserService.new)
app.use("/posts", PostService.new)
app.listen(3000) # http://127.0.0.1:3000
```

PATCH works without sending required fields, because `required_on` limits the requirement to create/update.

---

## Writing a custom adapter

To connect a real database, inherit from `Alumna::Service` and implement the six abstract methods. Each method receives the full `RuleContext` and returns a typed value.

```crystal
class PostgresUserService < Alumna::Service
  def initialize(@db : DB::Database)
    super(UserSchema)
    self.before(Authenticate)
  end

  def find(ctx : RuleContext) : Array(Hash(String, AnyData))
    # query @db using ctx.params for filtering
    [] of Hash(String, AnyData)
  end

  def get(ctx : RuleContext) : Hash(String, AnyData)?
    # query @db using ctx.id
    nil
  end

  def create(ctx : RuleContext) : Hash(String, AnyData)
    # insert ctx.data into @db, return the created record
    {} of String => AnyData
  end

  def update(ctx : RuleContext) : Hash(String, AnyData)
    # full replace of ctx.id with ctx.data
    {} of String => AnyData
  end

  def patch(ctx : RuleContext) : Hash(String, AnyData)
    # partial update of ctx.id with ctx.data
    {} of String => AnyData
  end

  def remove(ctx : RuleContext) : Bool
    # delete record at ctx.id, return true if deleted
    false
  end
end
```

---

## Serialization

Alumna supports JSON (default) and MessagePack out of the box. The format is negotiated per request using standard HTTP headers.

| Header | Role |
|---|---|
| `Content-Type: application/json` | Parse request body as JSON |
| `Content-Type: application/msgpack` | Parse request body as MessagePack |
| `Accept: application/json` | Respond with JSON |
| `Accept: application/msgpack` | Respond with MessagePack |

When no headers are present, the app-level default serializer is used (JSON unless overridden at construction time).

To add a new serialization format, implement `Alumna::Http::Serializer`:

```crystal
abstract class Serializer
  abstract def content_type : String
  abstract def encode(data : Hash(String, AnyData), io : IO) : Nil
  abstract def encode(data : Array(Hash(String, AnyData)), io : IO) : Nil
  abstract def decode(io : IO) : Hash(String, AnyData)
end
```

---

## Roadmap

### v0.3 - Solid foundation
- Polishing everything in the initial implementation

### v0.4 - Security and authentication
- JWT authentication helper rule
- session authentication helper rule

### v0.5 - First real database adapter: SQLite
- SQLite adapter for lightweight single-file deployments
- Using [crystal-sqlite3](https://github.com/crystal-lang/crystal-sqlite3)
- Adapter reads the service schema to introspect column names and types
- Supports schema-driven migration hints (not full migration management, which is left to dedicated tools)

### v0.6 - MySQl and PostgreSQL database adapters
- MySQl adapter using [crystal-db](https://github.com/crystal-lang/crystal-db) and [crystal-mysql](https://github.com/crystal-lang/crystal-mysql)
- PostgreSQL adapter using [crystal-db](https://github.com/crystal-lang/crystal-db) and [crystal-pg](https://github.com/will/crystal-pg)
- Adapter reads the service schema to introspect column names and types
- Supports schema-driven migration hints (not full migration management, which is left to dedicated tools)

### v0.7 - Real-time events via WebSocket
- Emit service events automatically after successful mutations (`created`, `updated`, `patched`, `removed`)
- Allow clients to subscribe to specific service paths over a WebSocket connection
- Rules gain access to an `event` field on the context to suppress or transform events before they are emitted
- Provider field on context already distinguishes `"rest"` from `"websocket"` in preparation for this

### v0.8 - Redis adapter for cache
- Redis adapter using [jgaskins/redis](https://github.com/jgaskins/redis)

### v0.9 - NATS integration for horizontal scaling
- Stateless service instances publish events to NATS subjects mirroring the service path and method (e.g. `alumna.users.created`)
- WebSocket gateway subscribes to NATS and fans events out to connected clients
- Enables multiple Alumna instances behind a load balancer to correctly propagate real-time events across all nodes
- NATS chosen over AMQP for operational simplicity and natural subject-based routing

### v0.10 - Automated test helpers
- `Alumna::Testing::ServiceClient` - call service methods directly without an HTTP layer, for fast unit tests
- `Alumna::Testing::RuleRunner` - execute a single rule against a fabricated context and assert on the result
- Spec helpers for asserting on context state after dispatch



### Future
- MongoDB adapter using [cryomongo](https://github.com/elbywan/cryomongo) or [moongoon](https://github.com/elbywan/moongoon)
- CLI scaffolding tool (`alumna new`, `alumna generate service`)

---

## Design decisions and trade-offs

**Why rules instead of middleware?** Middleware in most frameworks is a general-purpose mechanism with implicit ordering and no declared intent. A rule has an explicit phase (`before`, `after`, or `error`), an explicit target (all methods or a named subset), and a contract that returns a typed result. The intent is visible from the registration site.

**Why no resolvers?** FeathersJS resolvers automatically transform the result payload based on the requesting context. Alumna omits them in favour of explicit after-rules that transform `ctx.result` directly. This is slightly more code in trivial cases but significantly easier to debug and reason about when something goes wrong.

**Why `ServiceResult` uses `AnyData` instead of `JSON::Any`?** 

Alumna defines its own recursive union:

```crystal
alias AnyData = Nil | Bool | Int64 | Float64 | String | Array(AnyData) | Hash(String, AnyData)
alias ServiceResult = Hash(String, AnyData) | Array(Hash(String, AnyData)) | Nil
```

This lets every layer - context, services, rules, and serializers - work with native Crystal values instead of a wrapper type. The responder can dispatch on the actual type, MessagePack serializes without unwrapping, and validation errors flow through as plain hashes. It removes the `JSON::Any` dependency from the core, makes the context format-agnostic, and gives the compiler full visibility into data shapes for better errors and zero-cost abstractions.

**Why Crystal?** Expressive syntax that lowers the barrier for developers coming from Ruby or TypeScript. AOT compilation and a single binary output that eliminates runtime dependency management at deploy time. Performance that competes with Go, C and Rust _(see [LangArena](https://kostya.github.io/LangArena/))_ without sacrificing readability. The type system catches a large class of bugs at compile time that dynamic languages surface only in production.

---

## Contributing

Alumna is in early development and contributions are very welcome. Please open an issue before starting significant work so we can align on direction.

```bash
git clone https://github.com/alumna/backend
cd alumna
shards install
crystal spec
```

---

## License

MIT
