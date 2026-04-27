# Alumna Backend changelog

## 0.3.3 - 2026-04-27

* perf: improved rules dispatching processing and execution

## 0.3.2 - 2026-04-27

* fix: improved CORS rule

## 0.3.1 - 2026-04-27

* fix: improved rate limiting rule

## 0.3.0 - 2026-04-27

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
