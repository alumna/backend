![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/alumna/backend/ci.yml) [![codecov](https://codecov.io/gh/alumna/backend/graph/badge.svg?token=GX1Z8DNR3W)](https://codecov.io/gh/alumna/backend) ![Dynamic YAML Badge](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Falumna%2Fbackend%2Frefs%2Fheads%2Fmaster%2Fshard.yml&query=version&prefix=v&label=version) ![GitHub License](https://img.shields.io/github/license/alumna/backend)

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

**Supported formats:** `:email`, `:url`, `:uuid`

**Supported constraints:** `required`, `required_on`, `min_length`, `max_length`, `format`

`required_on` lets a field be required only for specific operations — perfect for PATCH:

```crystal
PostSchema = Alumna::Schema.new
  .str("title", required_on: [:create, :update], min_length: 1, max_length: 200)
  .str("body",  required_on: [:create, :update], min_length: 1)
```

**Required by default**

All fields are required unless you pass `required: false` or limit them with `required_on`. This matches Crystal's philosophy of failing fast — you opt out of validation, not into it.

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
  next Alumna::RuleResult.continue if errors.empty?
  details = errors.to_h { |e| {e.field, e.message} }
  Alumna::RuleResult.stop(Alumna::ServiceError.unprocessable("Validation failed", details))
end
```

Because it receives `ctx.method`, it automatically respects `required_on: [:create, :update]`. Use it directly in your service:

```crystal
class UserService < Alumna::MemoryAdapter
  def initialize
    super("/users", UserSchema)
    before Alumna.validate(UserSchema), only: [:create, :update, :patch]
  end
end
```

You still keep full control - write your own rule when you need custom messages, transformations, or conditional validation. `Alumna.validate` is just a zero-magic shortcut for the 90% case.

### Validation: custom validator

Schemas are plain objects. When needed, inside your own rule, call `schema.validate(data, method)` to get back an `Array(Alumna::FieldError)`. Pass the current `ctx.method` so `required_on` is respected:

```crystal
errors = PostSchema.validate(ctx.data, ctx.method)
```

---

### Rules

A rule is a `Proc` that receives a `RuleContext` and returns a `RuleResult`. Rules are values, not classes — they are defined once and registered on one or more services.

```crystal
# A rule that checks for a valid bearer token
Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "Bearer my-secret" ? Alumna::RuleResult.continue : Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized)
end

# An after-rule that adds a response header
AddRequestId = Alumna::Rule.new do |ctx|
  ctx.http.headers["X-Request-ID"] = Random::Secure.hex(8)
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
    super("/users", UserSchema)
    before Authenticate
    before Alumna.validate(UserSchema), only: [:create, :update, :patch]
    after AddRequestId
  end
end
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

---

### Application

```crystal
app = Alumna::App.new
app.use("/users", UserService.new)
app.listen(3000)
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
  token == "Bearer my-secret" ? Alumna::RuleResult.continue : Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized)
end

class UserService < Alumna::MemoryAdapter
  def initialize
    super("/users", UserSchema)
    before Authenticate
    before Alumna.validate(UserSchema), only: [:create, :update, :patch]
  end
end

class PostService < Alumna::MemoryAdapter
  def initialize
    super("/posts", PostSchema)
    before Authenticate
    before Alumna.validate(PostSchema), only: [:create, :update, :patch]

  end
end

app = Alumna::App.new
app.use("/users", UserService.new)
app.use("/posts", PostService.new)
app.listen(3000)
```

PATCH works without sending required fields, because `required_on` limits the requirement to create/update.

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

### v0.3 — First real database adapter: SQLite
- SQLite adapter for lightweight single-file deployments
- Using [crystal-sqlite3](https://github.com/crystal-lang/crystal-sqlite3)
- Adapter reads the service schema to introspect column names and types
- Supports schema-driven migration hints (not full migration management, which is left to dedicated tools)

### v0.4 — MySQl and PostgreSQL database adapters
- MySQl adapter using [crystal-db](https://github.com/crystal-lang/crystal-db) and [crystal-mysql](https://github.com/crystal-lang/crystal-mysql)
- PostgreSQL adapter using [crystal-db](https://github.com/crystal-lang/crystal-db) and [crystal-pg](https://github.com/will/crystal-pg)
- Adapter reads the service schema to introspect column names and types
- Supports schema-driven migration hints (not full migration management, which is left to dedicated tools)

### v0.5 — Real-time events via WebSocket
- Emit service events automatically after successful mutations (`created`, `updated`, `patched`, `removed`)
- Allow clients to subscribe to specific service paths over a WebSocket connection
- Rules gain access to an `event` field on the context to suppress or transform events before they are emitted
- Provider field on context already distinguishes `"rest"` from `"websocket"` in preparation for this

### v0.6 - Redis adapter for cache
- Redis adapter using [jgaskins/redis](https://github.com/jgaskins/redis)

### v0.6 — NATS integration for horizontal scaling
- Stateless service instances publish events to NATS subjects mirroring the service path and method (e.g. `alumna.users.created`)
- WebSocket gateway subscribes to NATS and fans events out to connected clients
- Enables multiple Alumna instances behind a load balancer to correctly propagate real-time events across all nodes
- NATS chosen over AMQP for operational simplicity and natural subject-based routing

### v0.7 — Automated test helpers
- `Alumna::Testing::ServiceClient` — call service methods directly without an HTTP layer, for fast unit tests
- `Alumna::Testing::RuleRunner` — execute a single rule against a fabricated context and assert on the result
- Spec helpers for asserting on context state after dispatch



### Future
- MongoDB adapter using [cryomongo](https://github.com/elbywan/cryomongo) or [moongoon](https://github.com/elbywan/moongoon)
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