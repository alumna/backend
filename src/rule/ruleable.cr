module Alumna
  module Ruleable
    alias RuleMap = Hash(ServiceMethod?, Hash(RulePhase, Array(Rule)))

    @rules : RuleMap = RuleMap.new

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

    # --- used by dispatch ---

    def collect_rules(method : ServiceMethod, phase : RulePhase) : Array(Rule)
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

    private def normalize_methods(only) : Array(ServiceMethod)
      only.map { |m| m.is_a?(Symbol) ? ServiceMethod.parse(m.to_s.capitalize) : m }
    end
  end
end
