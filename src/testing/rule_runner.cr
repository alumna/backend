module Alumna
  module Testing
    record RuleRunnerResult, ctx : RuleContext, error : ServiceError?

    # Executes a single Rule against a context and returns a result wrapper
    # containing both the mutated context and the returned error (if any).
    def self.run_rule(
      rule : Rule,
      ctx : RuleContext? = nil,
      **kwargs,
    ) : RuleRunnerResult
      target_ctx = ctx || build_ctx(**kwargs)
      err = rule.call(target_ctx)

      # Emulate the Orchestrator behavior by attaching the error to the context
      target_ctx.error = err if err

      RuleRunnerResult.new(target_ctx, err)
    end
  end
end
