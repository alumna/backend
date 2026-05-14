module Alumna
  abstract class Service
    include Ruleable

    property path : String = ""
    getter schema : Schema?

    # Merged pipelines built by App.use
    @before_pipeline : Array(Array(Rule))
    @after_pipeline : Array(Array(Rule))
    @error_pipeline : Array(Array(Rule))
    @before_app_len : Array(Int32)
    @error_svc_len : Array(Int32)

    def initialize(@schema : Schema? = nil)
      size = ServiceMethod.values.size
      @before_pipeline = Array.new(size) { [] of Rule }
      @after_pipeline = Array.new(size) { [] of Rule }
      @error_pipeline = Array.new(size) { [] of Rule }
      @before_app_len = Array.new(size, 0)
      @error_svc_len = Array.new(size, 0)
    end

    # ---- convenience helpers ----

    def validate(schema : Schema? = nil) : Rule
      s = schema || self.schema
      raise ArgumentError.new("validate requires a schema - service has none and none was passed") unless s
      Alumna.validate(s)
    end

    # -----------------------------

    abstract def find(ctx : RuleContext) : Array(Hash(String, AnyData))
    abstract def get(ctx : RuleContext) : Hash(String, AnyData)?
    abstract def create(ctx : RuleContext) : Hash(String, AnyData)
    abstract def update(ctx : RuleContext) : Hash(String, AnyData)
    abstract def patch(ctx : RuleContext) : Hash(String, AnyData)
    abstract def remove(ctx : RuleContext) : Bool

    def set_before_pipeline(method : ServiceMethod, app_rules : Array(Rule), svc_rules : Array(Rule))
      idx = method.value
      @before_pipeline[idx] = app_rules + svc_rules
      @before_app_len[idx] = app_rules.size
    end

    def set_after_pipeline(method : ServiceMethod, svc_rules : Array(Rule), app_rules : Array(Rule))
      @after_pipeline[method.value] = svc_rules + app_rules
    end

    def set_error_pipeline(method : ServiceMethod, svc_rules : Array(Rule), app_rules : Array(Rule))
      idx = method.value
      @error_pipeline[idx] = svc_rules + app_rules
      @error_svc_len[idx] = svc_rules.size
    end

    def before_pipeline(method) : Array(Rule)
      @before_pipeline[method.value]
    end

    def after_pipeline(method) : Array(Rule)
      @after_pipeline[method.value]
    end

    def error_pipeline(method) : Array(Rule)
      @error_pipeline[method.value]
    end

    def before_app_len(method) : Int32
      @before_app_len[method.value]
    end

    def error_svc_len(method) : Int32
      @error_svc_len[method.value]
    end

    protected def call_method(ctx : RuleContext) : {ServiceResult, ServiceError?}
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
        removed = {"removed" => remove(ctx)} of String => AnyData
        {removed, nil}
      when .options? then { {} of String => AnyData, nil }
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
