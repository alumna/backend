# Alumna Backend changelog

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
