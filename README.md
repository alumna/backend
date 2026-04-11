# Alumna

A minimalist, service-oriented backend framework for [Crystal](https://crystal-lang.org), inspired by the core architecture of [FeathersJS](https://feathersjs.com) and designed around three ideas: simplicity, explicitness, and performance.

---

## Philosophy

Most backend frameworks ask you to learn their full architecture before you can write a single working endpoint. Alumna takes the opposite approach.

The entire model fits in your head at once:

- A **Service** exposes a standard set of methods (`find`, `get`, `create`, `update`, `patch`, `remove`) and is automatically mounted as a RESTful HTTP API at a given path.
- A **Rule** is a single-responsibility function that receives a request context, applies one concern — authentication, validation, rate limiting, logging — and returns either `continue` or `stop`. Rules do not call each other; a flat orchestrator sequences them.
- A **Schema** describes the shape of a service's data. It is used for input validation inside rules and as a structural hint for storage adapters.

There is no magic, no dependency injection container, no decorator metadata, no resolver chain. Every moving piece is visible and explicit. A developer new to the codebase can read a service definition and understand the full execution path in minutes.

Alumna inherits Crystal's performance characteristics: ahead-of-time compilation, a single self-contained binary, no runtime dependencies, and throughput that benchmarks consistently alongside Go and Rust - with a syntax closer to Ruby.

---

## Status

Alumna is in active early development. The HTTP layer, rule pipeline, schema validation, in-memory adapter, and JSON/MessagePack serialization are complete and tested. See the [Roadmap](#roadmap) for what is coming next.

---

## Installation

Add Alumna to your `shard.yml`:

```yaml
dependencies:
  alumna:
    github: alumna/backend

  # Optional: only required if you want MessagePack support
  msgpack:
    github: crystal-community/msgpack-crystal
```

Then run:

```bash
shards install
```

Require it in your project:

```crystal
require "alumna"
```

Crystal 1.9 or later is required.

---

## Core concepts

### Schema

A schema describes the fields a service works with. It is used by rules for input validation and by adapters to understand the record structure.

```crystal
UserSchema = Alumna::Schema.new
  .field("name",  Alumna::FieldType::Str,  required: true,  min_length: 2, max_length: 100)
  .field("email", Alumna::FieldType::Str,  required: true,  format: Alumna::FieldFormat::Email)
  .field("age",   Alumna::FieldType::Int,  required: false)
  .field("admin", Alumna::FieldType::Bool, required: false)
```

**Supported field types:** `Str`, `Int`, `Float`, `Bool`, `Nullable`

**Supported formats:** `Email`, `Url`, `Uuid`

**Supported constraints:** `required`, `min_length`, `max_length`, `format`

Schemas are plain objects. You can pass them to a rule explicitly and call `schema.validate(ctx.data)` to get back an `Array(Alumna::FieldError)`, each carrying a `field` name and a `message`.

---

### Rules

A rule is a `Proc` that receives a `RuleContext` and returns a `RuleResult`. Rules are values, not classes — they are defined once and registered on one or more services.

```crystal
# A rule that checks for a valid bearer token
Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  if token == "Bearer my-secret"
    Alumna::RuleResult.continue
  else
    Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized)
  end
end

# A rule that validates the request body against a schema
ValidateUser = Alumna::Rule.new do |ctx|
  errors = UserSchema.validate(ctx.data)
  if errors.empty?
    Alumna::RuleResult.continue
  else
    details = errors.each_with_object({} of String => String) do |e, h|
      h[e.field] = e.message
    end
    Alumna::RuleResult.stop(Alumna::ServiceError.unprocessable("Validation failed", details))
  end
end

# A rule that logs every completed response
LogRequest = Alumna::Rule.new do |ctx|
  puts "[#{ctx.method}] #{ctx.path}"
  Alumna::RuleResult.continue
end
```

**What is available on the context:**

| Field | Type | Description |
|---|---|---|
| `ctx.app` | `App` | The application instance |
| `ctx.service` | `Service` | The service handling this request |
| `ctx.path` | `String` | The service path, e.g. `"/users"` |
| `ctx.method` | `ServiceMethod` | `Find`, `Get`, `Create`, `Update`, `Patch`, `Remove` |
| `ctx.phase` | `RulePhase` | `Before`, `After`, or `Error` |
| `ctx.params` | `Hash(String, String)` | Query string parameters |
| `ctx.headers` | `Hash(String, String)` | Request headers, lowercased |
| `ctx.id` | `String?` | Record ID from the URL, if present |
| `ctx.data` | `Hash(String, AnyData)` | Parsed request body |
| `ctx.result` | `ServiceResult` | Response payload; set this in a before-rule to skip the service call entirely |
| `ctx.error` | `ServiceError?` | Present when the pipeline is in the error phase |
| `ctx.http.status` | `Int32?` | Override the HTTP response status code |
| `ctx.http.headers` | `Hash(String, String)` | Add custom HTTP response headers |
| `ctx.http.location` | `String?` | Set to trigger an HTTP redirect |

**Signalling outcomes:**

```crystal
RuleResult.continue                              # proceed to the next rule or service method
RuleResult.stop(ServiceError.unauthorized)       # halt the pipeline and return an error response
RuleResult.stop(ServiceError.bad_request("...")) # halt with a custom error
```

**Available `ServiceError` constructors:**

```crystal
ServiceError.bad_request("message", details)  # 400
ServiceError.unauthorized("message")           # 401
ServiceError.forbidden("message")              # 403
ServiceError.not_found("message")              # 404
ServiceError.unprocessable("message", details) # 422
ServiceError.internal("message")               # 500
```

`details` is a `Hash(String, String)` for per-field error messages.

---

### Services

A service inherits from `Alumna::MemoryAdapter` (or from `Alumna::Service` directly when implementing a real storage adapter) and registers its rules in the constructor.

```crystal
class UserService < Alumna::MemoryAdapter
  def initialize
    super("/users", UserSchema)

    # Applied to every method, before the service call
    self.before(Authenticate)

    # Applied only to create, update, and patch
    self.before(
      ValidateUser,
      only: [
        Alumna::ServiceMethod::Create,
        Alumna::ServiceMethod::Update,
        Alumna::ServiceMethod::Patch,
      ]
    )

    # Applied to every method, after the service call
    self.after(LogRequest)
  end
end
```

**HTTP mapping:**

| Service method | HTTP verb | Path |
|---|---|---|
| `find(ctx)` | `GET` | `/users` |
| `get(ctx)` | `GET` | `/users/:id` |
| `create(ctx)` | `POST` | `/users` |
| `update(ctx)` | `PUT` | `/users/:id` |
| `patch(ctx)` | `PATCH` | `/users/:id` |
| `remove(ctx)` | `DELETE` | `/users/:id` |

Query parameters are available at `ctx.params`. The in-memory adapter applies simple equality filtering automatically, so `GET /users?admin=true` returns only records where `admin == "true"`.

---

### Application

```crystal
app = Alumna::App.new
app.use("/users", UserService.new)
app.listen(3000)
```

To use MessagePack as the default serializer for all responses:

```crystal
app = Alumna::App.new(serializer: Alumna::Http::MsgpackSerializer.new)
```

Clients can also negotiate the format per request using standard HTTP headers. `Content-Type` determines how the request body is parsed; `Accept` determines the response format.

---

## Full example

```crystal
# app.cr
require "alumna"

# ── Schemas ────────────────────────────────────────────────────────────────────

UserSchema = Alumna::Schema.new
  .field("name",  Alumna::FieldType::Str,  required: true,  min_length: 2, max_length: 100)
  .field("email", Alumna::FieldType::Str,  required: true,  format: Alumna::FieldFormat::Email)
  .field("age",   Alumna::FieldType::Int,  required: false)

PostSchema = Alumna::Schema.new
  .field("title", Alumna::FieldType::Str, required: true, min_length: 1, max_length: 200)
  .field("body",  Alumna::FieldType::Str, required: true, min_length: 1)

# ── Rules ──────────────────────────────────────────────────────────────────────

require "./rules/authenticate"
require "./rules/log_request"

# rules/authenticate.cr
Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  if token == "Bearer my-secret"
    Alumna::RuleResult.continue
  else
    Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized)
  end
end

# rules/log_request.cr
LogRequest = Alumna::Rule.new do |ctx|
  puts "[#{ctx.method}] #{ctx.path} (#{ctx.provider})"
  Alumna::RuleResult.continue
end

# ── Validation rules (schema-specific) ────────────────────────────────────────

ValidateUser = Alumna::Rule.new do |ctx|
  errors = UserSchema.validate(ctx.data)
  next Alumna::RuleResult.continue if errors.empty?
  details = errors.each_with_object({} of String => String) { |e, h| h[e.field] = e.message }
  Alumna::RuleResult.stop(Alumna::ServiceError.unprocessable("Validation failed", details))
end

ValidatePost = Alumna::Rule.new do |ctx|
  errors = PostSchema.validate(ctx.data)
  next Alumna::RuleResult.continue if errors.empty?
  details = errors.each_with_object({} of String => String) { |e, h| h[e.field] = e.message }
  Alumna::RuleResult.stop(Alumna::ServiceError.unprocessable("Validation failed", details))
end

# ── Services ───────────────────────────────────────────────────────────────────

class UserService < Alumna::MemoryAdapter
  def initialize
    super("/users", UserSchema)
    self.before(Authenticate)
    self.before(ValidateUser, only: [
      Alumna::ServiceMethod::Create,
      Alumna::ServiceMethod::Update,
      Alumna::ServiceMethod::Patch,
    ])
    self.after(LogRequest)
  end
end

class PostService < Alumna::MemoryAdapter
  def initialize
    super("/posts", PostSchema)
    self.before(Authenticate)
    self.before(ValidatePost, only: [
      Alumna::ServiceMethod::Create,
      Alumna::ServiceMethod::Update,
      Alumna::ServiceMethod::Patch,
    ])
    self.after(LogRequest)
  end
end

# ── App ────────────────────────────────────────────────────────────────────────

app = Alumna::App.new
app.use("/users", UserService.new)
app.use("/posts", PostService.new)
app.listen(3000)
```

**Example requests:**

```bash
# Create a user
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -H "authorization: Bearer my-secret" \
  -d '{"name": "Alice", "email": "alice@example.com", "age": 30}'

# List all users
curl http://localhost:3000/users -H "authorization: Bearer my-secret"

# Get a specific user
curl http://localhost:3000/users/1 -H "authorization: Bearer my-secret"

# Partial update
curl -X PATCH http://localhost:3000/users/1 \
  -H "Content-Type: application/json" \
  -H "authorization: Bearer my-secret" \
  -d '{"name": "Alice Smith"}'

# Delete
curl -X DELETE http://localhost:3000/users/1 -H "authorization: Bearer my-secret"

# Validation error
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -H "authorization: Bearer my-secret" \
  -d '{"name": "A"}'
# → 422 {"error":"Validation failed","details":{"name":"must be at least 2 characters","email":"is required"}}

# Missing token
curl http://localhost:3000/users
# → 401 {"error":"Unauthorized","details":{}}
```

---

## Writing a custom adapter

To connect a real database, inherit from `Alumna::Service` and implement the six abstract methods. Each method receives the full `RuleContext` and returns a typed value.

```crystal
class PostgresUserService < Alumna::Service
  def initialize(@db : DB::Database)
    super("/users", UserSchema)
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

### v0.2 — Real-time events via WebSocket
- Emit service events automatically after successful mutations (`created`, `updated`, `patched`, `removed`)
- Allow clients to subscribe to specific service paths over a WebSocket connection
- Rules gain access to an `event` field on the context to suppress or transform events before they are emitted
- Provider field on context already distinguishes `"rest"` from `"websocket"` in preparation for this

### v0.3 — NATS integration for horizontal scaling
- Stateless service instances publish events to NATS subjects mirroring the service path and method (e.g. `alumna.users.created`)
- WebSocket gateway subscribes to NATS and fans events out to connected clients
- Enables multiple Alumna instances behind a load balancer to correctly propagate real-time events across all nodes
- NATS chosen over AMQP for operational simplicity and natural subject-based routing

### v0.4 — Automated test helpers
- `Alumna::Testing::ServiceClient` — call service methods directly without an HTTP layer, for fast unit tests
- `Alumna::Testing::RuleRunner` — execute a single rule against a fabricated context and assert on the result
- Spec helpers for asserting on context state after dispatch

### v0.5 — First real database adapter
- PostgreSQL adapter using [crystal-db](https://github.com/crystal-lang/crystal-db) and [crystal-pg](https://github.com/will/crystal-pg)
- Adapter reads the service schema to introspect column names and types
- Supports schema-driven migration hints (not full migration management, which is left to dedicated tools)

### Future
- SQLite adapter (lightweight single-file deployments)
- MongoDB adapter
- Rate limiting rule built into the framework core
- JWT authentication helper rule
- CLI scaffolding tool (`alumna new`, `alumna generate service`)

---

## Design decisions and trade-offs

**Why rules instead of middleware?** Middleware in most frameworks is a general-purpose mechanism with implicit ordering and no declared intent. A rule has an explicit phase (`before` or `after`), an explicit target (all methods or a named subset), and a contract that returns a typed result. The intent is visible from the registration site.

**Why no resolvers?** FeathersJS resolvers automatically transform the result payload based on the requesting context. Alumna omits them in favour of explicit after-rules that transform `ctx.result` directly. This is slightly more code in trivial cases but significantly easier to debug and reason about when something goes wrong.

**Why `ServiceResult` instead of `JSON::Any` for the result type?** A typed union of `Hash | Array | Nil` lets the responder dispatch on the actual type rather than inspecting a wrapped value at runtime. It also removes the dependency on `JSON::Any` internals from the context, making the context format-agnostic.

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