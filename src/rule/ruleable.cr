module Alumna
  module Ruleable
    # Eager, non-nilable storage - each App/Service gets its own hashes
    @before_rules = Hash(ServiceMethod, Array(Rule)).new { |h, k| h[k] = [] of Rule }
    @after_rules = Hash(ServiceMethod, Array(Rule)).new { |h, k| h[k] = [] of Rule }
    @error_rules = Hash(ServiceMethod, Array(Rule)).new { |h, k| h[k] = [] of Rule }

    # ---- public API ----

    def before(rule : Rule, on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil)
      register_rule(:before, rule, on)
      self
    end

    def before(on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil, & : RuleContext -> _)
      before(Rule.new { |ctx| yield(ctx).as(ServiceError?) }, on: on)
    end

    def after(rule : Rule, on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil)
      register_rule(:after, rule, on)
      self
    end

    def after(on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil, & : RuleContext -> _)
      after(Rule.new { |ctx| yield(ctx).as(ServiceError?) }, on: on)
    end

    def error(rule : Rule, on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil)
      register_rule(:error, rule, on)
      self
    end

    def error(on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil, & : RuleContext -> _)
      error(Rule.new { |ctx| yield(ctx).as(ServiceError?) }, on: on)
    end

    # ---- internals ----
    def collect_rules(method : ServiceMethod, phase : RulePhase) : Array(Rule)
      case phase
      in RulePhase::Before then @before_rules[method]
      in RulePhase::After  then @after_rules[method]
      in RulePhase::Error  then @error_rules[method]
      end
    end

    private def register_rule(phase : Symbol, rule : Rule, on)
      target = case phase
               when :before then @before_rules
               when :after  then @after_rules
               when :error  then @error_rules
               else
                 raise "BUG: Ruleable.register_rule invalid phase #{phase.inspect}"
               end

      expand_on(on).each { |m| target[m] << rule }
    end

    private def expand_on(on) : Array(ServiceMethod)
      return ServiceMethod.values.reject(&.options?) if on.nil?

      items = on.is_a?(Array) ? on : [on]
      items.flat_map do |item|
        case item
        when ServiceMethod then [item]
        when :read         then [ServiceMethod::Find, ServiceMethod::Get]
        when :write        then [ServiceMethod::Create, ServiceMethod::Update, ServiceMethod::Patch, ServiceMethod::Remove]
        when :all          then ServiceMethod.values.reject(&.options?)
        when Symbol        then [ServiceMethod.parse(item.to_s)]
        else                    [] of ServiceMethod
        end
      end.uniq!
    end
  end
end
