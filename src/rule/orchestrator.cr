module Alumna
  module Orchestrator
    def self.run(rules : Array(Rule), ctx : RuleContext, short_circuit = false) : Bool
      i = 0
      size = rules.size
      while i < size
        result = rules.unsafe_fetch(i).call(ctx)
        if result.stop?
          ctx.error = result.error
          return false
        end
        return true if short_circuit && ctx.result_set?
        i += 1
      end
      true
    end

    def self.run_bounded(rules : Array(Rule), ctx : RuleContext, boundary : Int32, short_circuit = false) : {Bool, Bool}
      i = 0
      size = rules.size
      while i < size
        result = rules.unsafe_fetch(i).call(ctx)
        if result.stop?
          ctx.error = result.error
          return {false, i < boundary}
        end
        return {true, false} if short_circuit && ctx.result_set?
        i += 1
      end
      {true, false}
    end
  end
end
