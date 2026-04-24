module Alumna
  abstract class Service
    include Ruleable

    getter path : String
    getter schema : Schema?

    def initialize(@path : String, @schema : Schema? = nil)
    end

    abstract def find(ctx : RuleContext) : Array(Hash(String, AnyData))
    abstract def get(ctx : RuleContext) : Hash(String, AnyData)?
    abstract def create(ctx : RuleContext) : Hash(String, AnyData)
    abstract def update(ctx : RuleContext) : Hash(String, AnyData)
    abstract def patch(ctx : RuleContext) : Hash(String, AnyData)
    abstract def remove(ctx : RuleContext) : Bool

    def dispatch(ctx : RuleContext) : RuleContext
      # 1. before
      Orchestrator.run(collect_rules(ctx.method, RulePhase::Before), ctx)
      if ctx.error
        ctx.phase = RulePhase::Error
        Orchestrator.run(collect_rules(ctx.method, RulePhase::Error), ctx)
        return ctx
      end

      # 2. service method — only if no result yet
      unless ctx.result_set?
        ctx.phase = RulePhase::After
        result, error = call_method(ctx)
        if error
          ctx.error = error
          ctx.phase = RulePhase::Error
          Orchestrator.run(collect_rules(ctx.method, RulePhase::Error), ctx)
          return ctx
        end
        ctx.result = result
      end

      # 3. after — always runs on success, even on short-circuit
      ctx.phase = RulePhase::After
      Orchestrator.run(collect_rules(ctx.method, RulePhase::After), ctx)
      ctx
    end

    private def call_method(ctx : RuleContext) : {ServiceResult, ServiceError?}
      case ctx.method
      when .find? then {find(ctx), nil}
      when .get?
        result = get(ctx)
        raise ServiceError.not_found unless result
        {result, nil}
      when .create? then {create(ctx), nil}
      when .update? then {update(ctx), nil}
      when .patch?  then {patch(ctx), nil}
      when .remove?
        { {"removed" => remove(ctx)} of String => AnyData, nil }
      else
        {nil, ServiceError.internal("Unknown service method")}
      end
    rescue ex : ServiceError
      {nil, ex}
    rescue ex : Exception
      {nil, ServiceError.internal(ex.message || "Unexpected error")}
    end
  end
end
