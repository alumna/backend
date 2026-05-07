# Alumna Backend changelog

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
