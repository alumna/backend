module Alumna
  VERSION = "0.1.0"
end

# Core enums and primitives first — no dependencies
require "./core/types"
require "./service/method"
require "./rule/phase"
require "./service/error"

# Schema — depends only on primitives
require "./schema/base"
require "./schema/validator"

# Rule — depends on phase; context not yet defined, Rule is just a Proc alias
require "./rule/base"

# Context — depends on App, Service, ServiceMethod, RulePhase, ServiceError, HttpOverrides
# App and Service are forward-referenced here, so they must be required immediately after
require "./service/context"
require "./app"

# Orchestrator — depends on Rule, RuleContext
require "./rule/orchestrator"

# Service base — depends on everything above
require "./service/base"

# Adapter — depends on Service base
require "./adapter/memory"

# HTTP layer — depends on everything above
require "./http/serializer"
require "./http/serializers/json_serializer"
require "./http/serializers/msgpack_serializer"
require "./http/router"
require "./http/responder"
