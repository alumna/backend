module Alumna
  VERSION = "0.2.5"

  def self.validate(schema : Schema) : Rule
    Rule.new do |ctx|
      errors = schema.validate(ctx.data, ctx.method)
      next RuleResult.continue if errors.empty?
      details = errors.each_with_object({} of String => AnyData) { |e, h| h[e.field] = e.message }
      RuleResult.stop(ServiceError.unprocessable("Validation failed", details))
    end
  end
end

# Core enums and primitives — no dependencies
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

# Schema — depends only on primitives
require "./schema/base"
require "./schema/formats/registry"
require "./schema/formats/email"
require "./schema/formats/url"
require "./schema/formats/uuid"
require "./schema/validator"

# Context — now safe because App and Service exist as forward declarations
require "./service/context"

# Rule — now safe because RuleContext exists
require "./rule/base"
require "./rule/orchestrator"
require "./rule/ruleable"

# Full implementations — these reopen the forward-declared classes
require "./app"
require "./service/base"

# Adapter — depends on Service base
require "./adapter/memory"

# HTTP layer — depends on everything above
require "./http/serializer"
require "./http/serializers/json_serializer"
require "./http/serializers/msgpack_serializer"
require "./http/router"
require "./http/responder"
