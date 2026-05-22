module Alumna
  module Orchestrator
    def self.run(rules : Array(Rule), ctx : RuleContext, short_circuit = false, *, start : Int32 = 0) : Bool
      i = start
      size = rules.size
      while i < size
        if err = rules.unsafe_fetch(i).call(ctx)
          ctx.error = err
          return false
        end
        return true if short_circuit && ctx.result_set?
        i += 1
      end
      true
    end

    def self.run_bounded(rules : Array(Rule), ctx : RuleContext, boundary : Int32, short_circuit = false) : {ok: Bool, stopped_in_app: Bool}
      i = 0
      size = rules.size
      while i < size
        if err = rules.unsafe_fetch(i).call(ctx)
          ctx.error = err
          return {ok: false, stopped_in_app: i < boundary}
        end
        return {ok: true, stopped_in_app: false} if short_circuit && ctx.result_set?
        i += 1
      end
      {ok: true, stopped_in_app: false}
    end
  end
end
