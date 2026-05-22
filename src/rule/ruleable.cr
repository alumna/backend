module Alumna
  module Ruleable
    @frozen = Atomic(Bool).new(false)

    # Eager, non-nilable storage - each App/Service gets its own hashes
    @before_rules = Hash(ServiceMethod, Array(Rule)).new { |h, k| h[k] = [] of Rule }
    @after_rules = Hash(ServiceMethod, Array(Rule)).new { |h, k| h[k] = [] of Rule }
    @error_rules = Hash(ServiceMethod, Array(Rule)).new { |h, k| h[k] = [] of Rule }

    # Explicit method sets - used at boot time only, no runtime cost
    READ_METHODS  = [ServiceMethod::Find, ServiceMethod::Get]
    WRITE_METHODS = [ServiceMethod::Create, ServiceMethod::Update, ServiceMethod::Patch]
    ALL_METHODS   = ServiceMethod.values.reject(&.options?)

    def freeze_rules!
      @frozen.set(true)
    end

    private def ensure_not_frozen!
      if @frozen.get(:acquire)
        raise "Cannot register rules after pipelines are compiled (server is listening)"
      end
    end

    # ---- public API ----

    def before(rule : Rule, on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil)
      ensure_not_frozen!
      register_rule(RulePhase::Before, rule, on)
      self
    end

    def before(on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil, &block : RuleContext -> ServiceError?)
      before(block, on: on)
    end

    def after(rule : Rule, on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil)
      ensure_not_frozen!
      register_rule(RulePhase::After, rule, on)
      self
    end

    def after(on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil, &block : RuleContext -> ServiceError?)
      after(block, on: on)
    end

    def error(rule : Rule, on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil)
      ensure_not_frozen!
      register_rule(RulePhase::Error, rule, on)
      self
    end

    def error(on : ServiceMethod | Symbol | Array(ServiceMethod | Symbol) | Nil = nil, &block : RuleContext -> ServiceError?)
      error(block, on: on)
    end

    # ---- internals ----
    def collect_rules(method : ServiceMethod, phase : RulePhase) : Array(Rule)
      case phase
      in RulePhase::Before then @before_rules[method]
      in RulePhase::After  then @after_rules[method]
      in RulePhase::Error  then @error_rules[method]
      end
    end

    private def register_rule(phase : RulePhase, rule : Rule, on)
      target = case phase
               in RulePhase::Before then @before_rules
               in RulePhase::After  then @after_rules
               in RulePhase::Error  then @error_rules
               end

      expand_on(on).each { |m| target[m] << rule }
    end

    private def expand_on(on) : Array(ServiceMethod)
      return ALL_METHODS if on.nil?

      unless on.is_a?(Array)
        case on
        when ServiceMethod then return [on]
        when :read         then return READ_METHODS
        when :write        then return WRITE_METHODS
        when :all          then return ALL_METHODS
        when Symbol        then return [ServiceMethod.parse(on.to_s)]
        else                    return [] of ServiceMethod
        end
      end

      on.flat_map do |item|
        case item
        when ServiceMethod then [item]
        when :read         then READ_METHODS
        when :write        then WRITE_METHODS
        when :all          then ALL_METHODS
        when Symbol        then [ServiceMethod.parse(item.to_s)]
        else                    [] of ServiceMethod
        end
      end.uniq!
    end
  end
end
