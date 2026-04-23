module Alumna
  abstract class Service
    alias RuleMap = Hash(ServiceMethod?, Hash(RulePhase, Array(Rule)))

    getter path : String
    getter schema : Schema?

    def initialize(@path : String, @schema : Schema? = nil)
      @rules = RuleMap.new
    end

    # --- Rule registration API (symbol-friendly) ---

    # overload for single method
    def before(rule : Rule, only : ServiceMethod | Symbol) : self
      before(rule, only: [only])
    end

    def after(rule : Rule, only : ServiceMethod | Symbol) : self
      after(rule, only: [only])
    end

    # existing array version (unchanged, except it now also accepts symbols)
    def before(rule : Rule, only : Array(ServiceMethod | Symbol) = [] of ServiceMethod) : self
      methods = only.map { |m| m.is_a?(Symbol) ? ServiceMethod.parse(m.to_s.capitalize) : m }
      register_rule(RulePhase::Before, methods, rule)
      self
    end

    def after(rule : Rule, only : Array(ServiceMethod | Symbol) = [] of ServiceMethod) : self
      methods = only.map { |m| m.is_a?(Symbol) ? ServiceMethod.parse(m.to_s.capitalize) : m }
      register_rule(RulePhase::After, methods, rule)
      self
    end

    # --- Abstract service methods ---

    abstract def find(ctx : RuleContext) : Array(Hash(String, AnyData))
    abstract def get(ctx : RuleContext) : Hash(String, AnyData)?
    abstract def create(ctx : RuleContext) : Hash(String, AnyData)
    abstract def update(ctx : RuleContext) : Hash(String, AnyData)
    abstract def patch(ctx : RuleContext) : Hash(String, AnyData)
    abstract def remove(ctx : RuleContext) : Bool

    # --- Full request lifecycle ---

    def dispatch(ctx : RuleContext) : RuleContext
      # 1. Before rules
      run_rules(ctx, collect_rules(ctx.method, RulePhase::Before))
      return ctx if ctx.error || ctx.result_set?

      # 2. Service method call
      ctx.phase = RulePhase::After
      result, error = call_method(ctx)
      if error
        ctx.error = error
        ctx.phase = RulePhase::Error
        return ctx
      end
      ctx.result = result

      # 3. After rules
      run_rules(ctx, collect_rules(ctx.method, RulePhase::After))
      ctx
    end

    # --- Private ---

    # Returns the result and nil error on success, or nil result and a
    # ServiceError on failure. No exceptions cross this boundary.
    private def call_method(ctx : RuleContext) : {ServiceResult, ServiceError?}
      case ctx.method
      when .find?
        {find(ctx), nil}
      when .get?
        result = get(ctx)
        raise ServiceError.not_found unless result
        {result, nil}
      when .create?
        {create(ctx), nil}
      when .update?
        {update(ctx), nil}
      when .patch?
        {patch(ctx), nil}
      when .remove?
        # remove returns Bool — translate to a minimal result hash
        removed = remove(ctx)
        result = {"removed" => removed} of String => AnyData
        {result, nil}
      else
        {nil, ServiceError.internal("Unknown service method")}
      end
    rescue ex : ServiceError
      {nil, ex}
    rescue ex : Exception
      {nil, ServiceError.internal(ex.message || "Unexpected error")}
    end

    private def run_rules(ctx : RuleContext, rules : Array(Rule))
      Orchestrator.run(rules, ctx)
    end

    private def collect_rules(method : ServiceMethod, phase : RulePhase) : Array(Rule)
      global = @rules[nil]?.try(&.[phase]?) || [] of Rule
      specific = @rules[method]?.try(&.[phase]?) || [] of Rule
      global + specific
    end

    private def register_rule(phase : RulePhase, methods : Array(ServiceMethod), rule : Rule)
      targets = methods.empty? ? [nil] : methods.map(&.as(ServiceMethod?))
      targets.each do |target|
        @rules[target] ||= {} of RulePhase => Array(Rule)
        @rules[target][phase] ||= [] of Rule
        @rules[target][phase] << rule
      end
    end
  end
end
