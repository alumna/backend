module Alumna
  class Orchestrator
    def initialize(@rules : Array(Rule))
    end

    def run(ctx : RuleContext) : RuleContext
      @rules.each do |rule|
        result = rule.call(ctx)

        if result.stop?
          ctx.error = result.error
          ctx.phase = RulePhase::Error
          break
        end

        # A before-rule may short-circuit the service method call entirely by
        # setting ctx.result directly before returning RuleResult.continue.
        # The orchestrator stops processing further before-rules in that case,
        # and dispatch will skip the service method call. This is the intended
        # mechanism for caching, mocking, or access-controlled early returns.
        break if ctx.phase.before? && ctx.result_set?
      end

      ctx
    end
  end
end
