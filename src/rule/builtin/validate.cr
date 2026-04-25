module Alumna
  def self.validate(schema : Schema) : Rule
    Rule.new do |ctx|
      errors = schema.validate(ctx.data, ctx.method)
      next RuleResult.continue if errors.empty?
      details = errors.each_with_object({} of String => AnyData) { |e, h| h[e.field] = e.message }
      RuleResult.stop(ServiceError.unprocessable("Validation failed", details))
    end
  end
end
