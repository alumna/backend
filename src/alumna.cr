module Alumna
  VERSION = "0.3.4"
end

# Core enums and primitives - no dependencies
require "./core/types"
require "./service/method"
require "./rule/phase"
require "./service/error"

# --- Solving a circular dependency ---
# RuleContext needs App and Service as types, but App/Service need Rule.
# Forward-declare them so context can compile.
module Alumna
  class App; end

  abstract class Service; end
end

# Schema - depends only on primitives
require "./schema/base"
require "./schema/formats/registry"
require "./schema/formats/email"
require "./schema/formats/url"
require "./schema/formats/uuid"
require "./schema/validator"

# Context - safe because App and Service exist as forward declarations
require "./service/context"

# Rule - safe because RuleContext exists
require "./rule/base"
require "./rule/orchestrator"
require "./rule/ruleable"
require "./rule/builtin/validate"
require "./rule/builtin/cors"
require "./rule/builtin/rate_limiter"
require "./rule/builtin/logger"

# Full implementations - these reopen the forward-declared classes
require "./app"
require "./service/base"

# Adapter - depends on Service base
require "./adapter/memory"

# HTTP layer - depends on everything above
require "./http/serializer"
require "./http/serializers/json_serializer"
require "./http/serializers/msgpack_serializer"
require "./http/router"
require "./http/responder"
