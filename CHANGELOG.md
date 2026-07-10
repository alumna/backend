# Alumna Backend changelog

## 0.5.5 - 2026-07-09

### Added
* **schema:** Added support for `default` values. Defaults can be static primitives or dynamic blocks (Procs). The validation engine automatically injects them into missing fields during `CREATE` operations.
* **schema:** Introduced the `nullable: true` trait. This allows clients to explicitly send `null` values, which is distinctly handled from `required: false` (which allows omitting the key entirely).
* **schema:** Added `unique: true` and `indexed: true` field constraints to serve as structural hints for database adapters.
* **schema:** Added schema-level compound indexes via `Schema#index(["field1", "field2"], unique: true)`.
* **adapter:** The `MemoryAdapter` now strictly enforces `unique` constraints during `create`, `update`, and `patch` operations, safely returning a `422 Unprocessable Entity` on conflicts.

### Changed
* **schema:** `FieldDescriptor` is now a `class` instead of a `struct`. Because structs are passed by value in Crystal, the previous implementation was copying the entire descriptor (containing ~17 fields) onto the stack for every field, on every request. This change trades a one-time boot heap allocation for zero-copy reference passing during the validation hot-path.
* **schema:** Removed the redundant `@field_names` `Set`. Field existence checks now use the existing `@fields_by_name` hash directly, saving memory and eliminating a duplicated data structure.
* **schema:** `resolve_format` now utilizes a strictly typed `NamedTuple`, improving internal code clarity and preventing positional tuple errors.

### Performance
* **schema:** Completely rewrote nested path resolution (`Schema#find_field`). It now walks dot-notation and bracket-notation strings using zero-allocation `String#index` traversal, completely eliminating expensive `String#split` and Regex allocations during deep query filtering.
* **schema:** Optimized the core `_validate` loop. Loop-invariant HTTP method checks are now hoisted, default value injections avoid double hash lookups, and the path tracer uses an `ensure` block for faster, safer unwinding.
* **schema:** Added `@[AlwaysInline]` to validation helper methods (`check_type`, `required?`) to guarantee the compiler avoids method-call overhead inside the validation loop.
* **adapter:** `MemoryAdapter#check_unique` now uses `@store.each_value.any?`. This prevents the adapter from needlessly allocating a complete `Array` of the entire dataset on every `create`, `update`, or `patch` operation.
* **query:** `Query#parse_positive_int` now natively leverages `String#to_i?(whitespace: false)`, completing the parse and validation in a single, highly optimized pass.

## 0.5.4 - 2026-06-05

### Added
* **app:** Unix socket binding support! You can now serve Alumna via a local socket using `app.listen(unix_socket: "/tmp/app.sock")`. It can be run simultaneously with a TCP port or completely standalone.
* **context:** Inter-service communication via `RuleContext#call`. You can now elegantly call other mounted services completely in-memory (bypassing TCP/HTTP serialization) while still perfectly executing all target schemas and rules. `ctx.call("/users", :create, data)`
* **router:** Dynamic `provider` resolution. `ctx.provider` is now automatically set to `"local"` when requests arrive over a Unix socket, and `"rest"` over TCP, making it effortless to securely bypass authentication for local system requests.

### Changed
* **context:** Structural request properties (`provider`, `id`) are now securely locked down as read-only (`getter` instead of `property`) to prevent accidental or malicious mutation by downstream rules mid-flight.

## 0.5.3 - 2026-06-02

### Changed
* **fix:** adapter suite and memory adapter with comparison weights similar to real databases
* **refactor:** humanize adapter suite and isolated the custom JSON encode/decode
* **test:** coverage for json_helper convenience methods

## 0.5.2 - 2026-05-22

### Changed
* **views:** `HeadersView` and `ParamsView` now strictly adhere to Crystal conventions. Using `["key"]` raises a `KeyError` if the key is missing, while `["key"]?` safely returns `nil`. 
* **errors:** `ServiceError` now lazily allocates its `details` Hash. Standard control-flow errors (like 401, 404, 500) now execute with zero heap allocations for the details payload.
* **ruleable:** `register_rule` now strictly enforces the `RulePhase` enum rather than using Symbols, catching phase routing errors at compile time.
* **testing:** added explicit documentation to `AdapterSuiteHelpers.any` to clarify its role as a compiler type-casting workaround for nested literals.

### Performance
* **schema:** introduced an internal O(1) hash lookup (`@fields_by_name`) for `Schema#find_field`. Deep schema path resolution during query parsing is now significantly faster and no longer requires linear O(N) array scans.
* **schema:** completely rewrote the internal `Validator` loop to use idiomatic `case/when` type narrowing, eliminating repetitive `.is_a?` type checks.
* **cors:** replaced raw string comparison with zero-allocation `ctx.method.options?` enum checks.
* **ruleable:** added a fast-path to `expand_on` to eliminate intermediate array allocations when registering single rules, and optimized `ServiceMethod` parsing to avoid string capitalizations.

### Fixed
* **logger:** encapsulated the monotonic `START` constant inside a private `LoggerState` module, preventing it from polluting the public `Alumna` namespace.
* **views:** utilized a Crystal macro (`define_overlay_view`) to eliminate ~70 lines of duplicated code between `HeadersView` and `ParamsView`.
* **orchestrator:** `run_bounded` now returns a self-documenting `NamedTuple` (`{ok: Bool, stopped_in_app: Bool}`), drastically improving readability in the main dispatch loop with zero runtime penalty.
* **thread-safety:** `Ruleable#ensure_not_frozen!` now explicitly uses `:acquire` memory ordering to guarantee perfectly synchronized reads across threads.

## 0.5.1 - 2026-05-22

### Added
* **schema:** introduced `strict: true` (default) to automatically reject undeclared fields in request payloads, preventing Mass Assignment attacks.
* **schema:** introduced `read_only: true` constraint. Rejects client manipulation during writes (`POST/PUT/PATCH`) while safely waiving `required` checks.
* **rules:** added built-in `Alumna.timestamp` rule for effortless, automatic UTC date injection on creation or updates.
* **context:** `ctx.store` now accepts custom classes and structs safely alongside primitives by including the `Alumna::Storeable` module.
* **types:** `Time` and `Bytes` are now first-class citizens in the `AnyData` union, completely eliminating unnecessary string conversions.
* **docs:** clearly documented the framework's philosophical decision to strictly enforce flat routing for O(1) performance and predictable client-side caching.

### Changed
* **query:** query parameters are now deeply typed! `Query#typed_filters` uses the service's Schema to automatically coerce strings into `Int64`, `Float64`, `Bool`, and `Time`. This eliminates string-fallback bugs and perfectly sets up future SQL adapters.
* **http:** `remove` (DELETE) operations now return `nil` by default, natively mapping to a semantic `204 No Content` with an empty body, saving memory and payload allocations.
* **app:** rule pipelines are now strictly frozen upon server boot (`app.listen`). Attempting to register rules after compilation now throws an explicit exception rather than failing silently.
* **serializers:** refactored JSON and MessagePack serializers to encode/decode `Time` (RFC 3339) and `Bytes` directly to/from native Crystal types. Optimized `MsgpackSerializer` to fully leverage the `msgpack-crystal` shard internals.

### Performance
* **memory_adapter:** drastically reduced the scope of Mutex locks. `find` now shallow-copies the dataset and releases the lock instantly, allowing multi-threaded filtering and sorting without bottlenecking concurrent writes.
* **memory_adapter:** replaced intermediate array allocations with zero-allocation `String#index` slicing for dot-notation field extraction.
* **memory_adapter:** implemented tuple dispatch (`case {a, b}`) for high-speed, compiler-optimized type comparisons.
* **memory_adapter:** combined `$skip` and `$limit` into a single `Array#[]` memory copy (`copy_from`), replacing two separate array allocations while safely guarding against `IndexError`.
* **query:** removed multiple intermediate array allocations in `$sort` and `$select` parsing by utilizing `compact_map` and `String#index`.
* **context:** replaced repetitive `data_*?` typed accessors with a zero-runtime-cost compile-time macro loop.

### Fixed
* **tests:** expanded `AdapterSuite` to assert strict `400 Bad Request` responses on malicious type injections, and verified safe boundary limits for `$skip` pagination.

## 0.5.0 - 2026-05-18

### Added
* **schema:** introduced nested field validation. The `Schema` now fully supports nested objects via `.hash` and arrays (of both primitives and nested objects) via `.array`.
* **app:** graceful shutdown. `app.listen` now safely traps `SIGINT` and `SIGTERM`, waiting for active requests to finish before exiting, with a configurable `shutdown_timeout`.
* **app:** automatic multi-thread worker configuration when compiling with `-Dpreview_mt` and `-Dexecution_context`.
* **query:** comprehensive comparison operators. `Alumna::Query` now natively parses `$gt`, `$gte`, `$lt`, `$lte`, `$ne`, `$in`, and `$nin`.
* **tests:** CI/CD now tests the framework in both single-threaded and multi-threaded (`-Dpreview_mt`) environments.

### Changed
* **service:** eliminated Exception allocation on the hot path. `Service#call_method` now returns a `{ServiceResult, ServiceError?}` tuple instead of raising `ServiceError` for expected control flow (like 404s).
* **context:** resolved semantic ambiguity around `nil` results. Added an explicit `@result_set` flag to `RuleContext` so that a rule intentionally returning `nil` is indistinguishable from an unset result.
* **app:** `compile_pipelines!` is now strictly thread-safe. Secured with a `Sync::Mutex` to prevent race conditions during boot under multi-threaded environments.

### Fixed
* **adapter:** `MemoryAdapter#find` now uses type-aware comparison for `$sort`. Integers, floats, and booleans are sorted correctly by their actual values instead of falling back to lexicographic string sorting. Mismatched types safely fall back to string comparison.

### Performance
* **rules:** error pipelines are now pre-compiled at boot. Previously, error rules were collected dynamically on every error path. Now they share the exact same pre-compiled array walk as the `before` and `after` phases, ensuring symmetrical behavior and zero runtime allocations.

## 0.4.3 - 2026-05-11

### Changed
* **tests:** Massive refactor of the entire spec suite to utilize the new `Alumna::Testing` toolkit.
* **tests:** Eradicated massive amounts of boilerplate. Eliminated the need for mock `TestService` classes and manual context builders in rule tests (CORS, Logger, RateLimiter).
* **tests:** Replaced the legacy `test_ctx` helper with the robust `Alumna::Testing.build_ctx`.
* **tests:** Maintained 100% strict code coverage while reducing test codebase size and improving test readability.

## 0.4.2 - 2026-05-11

### Added
* **testing:** Introduced the `Alumna::Testing` toolkit to provide first-class testing ergonomics.
* **testing:** `AppClient` for blazing-fast, in-memory end-to-end testing without opening TCP sockets or requiring `sleep`.
* **testing:** `RuleRunner` (`Testing.run_rule`) to easily test individual rules in complete isolation.
* **testing:** `AdapterSuite` macro to automatically run universal compliance/behavior tests against any custom database adapter.
* **testing:** `Testing.build_ctx` helper for fabricating custom request contexts effortlessly.

### Changed
* **tests:** Migrated `MemoryAdapter` specs to use the new `AdapterSuite`.
* **tests:** Migrated Integration specs to use the new `AppClient`, drastically speeding up the suite.

## 0.4.1 - 2026-05-07

### Performance
* **router:** remove `http_verb.upcase` in `resolve_method` — HTTP methods are already uppercase per RFC 9110, saves one String allocation on every request
* **router:** `parse_xff` now builds the IP list in a single pass — eliminates `split.map.reject` intermediate arrays
* **router:** `parse_forwarded` now walks right-to-left respecting `trusted_proxies`, matching the XFF security model
* **serializers:** `from_content_type?` fast-path for lowercase `application/json` and `application/msgpack` — zero allocations for the common case, fallback to `downcase` only for rare casings
* **validator:** lazy error allocation — `validate` returns shared `EMPTY_ERRORS` on success, allocates only on first error; extracted `required?` and `push_error` to remove duplication
* **query:** `$limit`/`$skip` validation replaced `/\A\d+\z/` Regex with byte-level check (`each_byte { |b| 48 <= b <= 57 }`) — no Regex engine, no allocations, early exit on first non-digit
* **memory:** removed redundant `records.to_a` in `MemoryAdapter#find` — `@store.values` already returns a fresh Array

### Fixed
* **router:** `Forwarded: for="[::1]:1234"` was silently dropped — now correctly extracts IPv6 address and strips optional port
* **router:** `Forwarded` header previously returned leftmost IP without checking trust list — now correctly skips trusted proxies, preventing spoofing behind trusted load balancers

### Changed
* **serializers:** `Accept` matching remains simple substring search (no q-value parsing) — behavior unchanged, now documented and allocation-free

### Added
* **test:** create `spec/http/serializers_spec.cr` to cover serializer selection logic based on http headers

## 0.4.0 - 2026-05-07

### Added
* **service:** `validate` helper - `before validate, on: :write` uses the service's own schema, no duplication
* **context:** typed data accessors - `ctx.data_str?`, `ctx.data_int?`, `ctx.data_float?`, `ctx.data_bool?` for zero-cost, allocation-free reads in adapters
* **ruleable:** explicit `READ_METHODS` and `WRITE_METHODS` constants for clarity

### Changed
* **BREAKING - service:** `Service` no longer accepts `path` in `initialize`. Path is set once by `app.use`. Removes duplication across all adapters
* **BREAKING - rules:** `Rule` is now `Proc(RuleContext, ServiceError?)`. Return `nil` to continue, return `ServiceError` to stop. `RuleResult` removed from public API
* **rules:** `before`, `after`, `error` now accept blocks directly - `before { |ctx| ... }` compiles to the same proc with no extra allocation
* **services:** `Alumna.memory(schema) { ... }` yields the service for inline rule registration. Enables `app.use "/x", Alumna.memory(S) { ... }`
* **schema:** `required_on` accepts single symbol - `required_on: :create` works alongside `[:create, :update]`
* **ruleable:** `:write` now expands to `[Create, Update, Patch]` only - `Remove` is excluded by design, preventing accidental validation on DELETE
* **docs:** all examples updated to omit `required: true` (default) and use the new helpers

### Removed
* **public API:** `Alumna::RuleResult` - replaced by nullable `ServiceError` return

### Performance
* No changes to hot path - `Orchestrator.run_bounded` still uses `unsafe_fetch`, pipelines remain pre-compiled at `listen`. All eight simplifications are compile-time only

## 0.3.6 - 2026-05-05

### Fixed
* **app dispatch:** after-phase errors now run service error hooks before app error hooks, making error handling symmetrical across before/service/after phases
* **http responder:** 204 No Content and 304 Not Modified responses no longer include a body, per RFC 7230/7231; fixes CORS preflight returning `{}`
* **router:** paths are now normalized (`/items` == `/items/`), duplicate `app.use` mounts raise `ArgumentError`
* **limited_io:** limit enforcement now covers `read_byte`, `peek`, and `skip`; `peek` returns `Bytes.empty` at EOF instead of `nil`

### Added
* **query:** new `ctx.query` API with lazy parsing of `$limit`, `$skip`, `$sort`, `$select`; `MemoryAdapter#find` implements all four
* **tests:** full coverage for query parsing, path normalization, and LimitedIO lifecycle (`close`, `closed?`)

### Changed
* **cors:** global rules no longer run on OPTIONS by design; register with `only: :options` (or all methods) for preflights - documented and tested

## 0.3.5 - 2026-04-28

* refactor: HTTP `OPTIONS` verb is now native are correctly handled
* refactor: CORS implementation now makes correct use of HTTP `OPTIONS`
* fix: pre-compilation of rule pipelines are done at the `app.listen` phase or
       at the first dispatch, which comes first. This ensures that global rules
       registered after services registration are still added to them

## 0.3.0-0.3.4 - 2026-04-27

* perf: faster rules execution and optimizations on router `resolve_service` and `parse_forwarded`
* perf: improved rules dispatching processing and execution
* fix: improved CORS rule
* fix: improved rate limiting rule
* fix: solidified the proxy handling logic for real_ip reading
* fix: make http headers and params available with zero-allocation views

## 0.2.6 - 2026-04-26

* Now the essential contract is practically validated
* feat: built-in rules (#12)
* feat: error phase rules (#11)
* feat: global app rules (#10)
* refactor/feat: pluggable schema formats (#9)
* refactor: complete type-agnostic implementation, fully tested (#8)
* time to polish the many rough edges on v0.3.x

## 0.2.5 - 2026-04-20

* Test: Flow typing in spec tests

## 0.2.4 - 2026-04-18

* Test: covered `src/schema/base.cr`

## 0.2.3 - 2026-04-18

* Fix: make `format:` accept symbols like everything else in `src/schema/base.cr`

## 0.2.2 - 2026-04-18

* Automated tests on multiple critical parts of the framework

## 0.2.1 - 2026-04-18

* Docs: built-in validation rule

## 0.2.0 - 2026-04-17

* Optimizations:
    * `src/http/router.cr` - avoiding repeated instantiation of serializers
    * `src/schema/validator.cr` - avoiding repeated instantiation of regexes
    * `src/rule/orchestrator.cr` - changing it to a module
    * `src/service/base.cr` - make it to call `Orchestrator.run` directly, avoiding repeated object allocations and method instantiations

* Simplification of syntax allowing symbols for HTTP verbs like `:create`, `:update`, `:patch`, etc
* `Alumna.validate(<Schema>)` for cleaner validations
* First comprehensive integration test

## 0.1.6 - 2026-04-13

* Unit tests for the router at `src/http/router.cr`

## 0.1.5 - 2026-04-13

* Unit tests for serializers in `src/http/serializers/` (`json` and `msgpack`)
* Fix for `msgpack` serializer to not discard `nil` values

## 0.1.4 - 2026-04-13

* Unit tests for `dispatch` method in `src/service/base.cr`

## 0.1.3 - 2026-04-13

* Unit tests for `src/adapter/memory.cr`

## 0.1.2 - 2026-04-13

* Unit tests for `src/rule/orchestrator.cr`

## 0.1.1 - 2026-04-13

* Unit tests for `src/schema/validator.cr`
* Fix validator to check whether the result is `nil`, not whether it's truthy

## 0.1.0 - 2026-04-11

* First working release
