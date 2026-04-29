module Alumna
  module Ruleable
    alias RuleMap = Hash(ServiceMethod?, Hash(RulePhase, Array(Rule)))

    @rules : RuleMap = RuleMap.new

    # Built lazily to avoid compile-time enum lookup issues
    EMPTY_RULES = [] of Rule
    @compiled : Array(Array(Array(Rule)))? = nil

    # --- public API ---
    def before(rule : Rule, only : ServiceMethod | Symbol) : self
      before(rule, only: [only])
    end

    def after(rule : Rule, only : ServiceMethod | Symbol) : self
      after(rule, only: [only])
    end

    def before(rule : Rule, only : Array(ServiceMethod | Symbol) = [] of ServiceMethod) : self
      register_rule(RulePhase::Before, normalize_methods(only), rule)
      self
    end

    def after(rule : Rule, only : Array(ServiceMethod | Symbol) = [] of ServiceMethod) : self
      register_rule(RulePhase::After, normalize_methods(only), rule)
      self
    end

    def error(rule : Rule, only : ServiceMethod | Symbol) : self
      error(rule, only: [only])
    end

    def error(rule : Rule, only : Array(ServiceMethod | Symbol) = [] of ServiceMethod) : self
      register_rule(RulePhase::Error, normalize_methods(only), rule)
      self
    end

    # --- hot path ---
    def collect_rules(method : ServiceMethod, phase : RulePhase) : Array(Rule)
      ensure_compiled![method.value][phase.value]
    end

    private def register_rule(phase : RulePhase, methods : Array(ServiceMethod), rule : Rule)
      targets = methods.empty? ? [nil] : methods.map(&.as(ServiceMethod?))
      targets.each do |target|
        @rules[target] ||= {} of RulePhase => Array(Rule)
        @rules[target][phase] ||= [] of Rule
        @rules[target][phase] << rule

        if target.nil?
          ServiceMethod.values.each { |m| rebuild_index(m, phase) }
        else
          rebuild_index(target, phase)
        end
      end
    end

    private def rebuild_index(method : ServiceMethod, phase : RulePhase)
      compiled = ensure_compiled!
      global = @rules[nil]?.try(&.[phase]?) || EMPTY_RULES
      specific = @rules[method]?.try(&.[phase]?) || EMPTY_RULES
      # CONVENTION: OPTIONS is opt-in. Global rules (registered without `only:`)
      # apply to data methods only, not to preflights.
      compiled[method.value][phase.value] = method.options? ? specific : global + specific
    end

    # Returns the matrix, creating it once on first use
    private def ensure_compiled! : Array(Array(Array(Rule)))
      @compiled ||= Array.new(ServiceMethod.values.size) do
        Array.new(RulePhase.values.size) { EMPTY_RULES }
      end
    end

    private def normalize_methods(only) : Array(ServiceMethod)
      only.map { |m| m.is_a?(Symbol) ? ServiceMethod.parse(m.to_s.capitalize) : m }
    end
  end
end
