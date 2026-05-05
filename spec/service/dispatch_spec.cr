require "../spec_helper"

private class TrackedService < Alumna::MemoryAdapter
  getter called : Array(String)

  def initialize
    super()
    @called = [] of String
  end

  def find(ctx : Alumna::RuleContext) : Array(Hash(String, Alumna::AnyData))
    @called << "find"
    super
  end

  def create(ctx : Alumna::RuleContext) : Hash(String, Alumna::AnyData)
    @called << "create"
    super
  end

  def update(ctx : Alumna::RuleContext) : Hash(String, Alumna::AnyData)
    @called << "update"
    super
  end
end

private def make_ctx(
  app : Alumna::App,
  service : Alumna::Service,
  method : Alumna::ServiceMethod,
  id : String? = nil,
  data : Hash(String, Alumna::AnyData) = {} of String => Alumna::AnyData,
) : Alumna::RuleContext
  Alumna::RuleContext.new(
    app: app,
    service: service,
    path: service.path,
    method: method,
    phase: Alumna::RulePhase::Before,
    params: Alumna::Http::ParamsView.new(HTTP::Params.new),
    headers: Alumna::Http::HeadersView.new(HTTP::Headers.new),
    id: id,
    data: data
  )
end

private def dispatch(service, method, id = nil, data = {} of String => Alumna::AnyData, app = nil)
  app ||= Alumna::App.new
  mount_path = "/tracked" # TrackedService is always mounted here in this spec
  app.use(mount_path, service) unless app.services.has_key?(mount_path)
  ctx = make_ctx(app, service, method, id, data)
  app.dispatch(service, ctx)
  ctx
end

private def continuing_rule(log : Array(String), label : String) : Alumna::Rule
  Alumna::Rule.new do |ctx|
    log << label
    Alumna::RuleResult.continue
  end
end

private def stopping_rule(label : String) : Alumna::Rule
  Alumna::Rule.new do |ctx|
    Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized(label))
  end
end

private def result_setting_rule(label : String) : Alumna::Rule
  Alumna::Rule.new do |ctx|
    ctx.result = {"shortcut" => label} of String => Alumna::AnyData
    Alumna::RuleResult.continue
  end
end

describe "Dispatch" do
  describe "execution order" do
    it "runs before rules, then the service method, then after rules" do
      log = [] of String
      service = TrackedService.new
      service.before(continuing_rule(log, "before-1"))
      service.before(continuing_rule(log, "before-2"))
      service.after(continuing_rule(log, "after-1"))

      dispatch(service, Alumna::ServiceMethod::Find)

      log.should eq(["before-1", "before-2", "after-1"])
      service.called.should eq(["find"])
    end

    it "sets ctx.phase to After before calling the service method" do
      observed_phase = nil
      service = TrackedService.new
      service.after(Alumna::Rule.new do |ctx|
        observed_phase = ctx.phase
        Alumna::RuleResult.continue
      end)

      dispatch(service, Alumna::ServiceMethod::Find)
      observed_phase.should eq(Alumna::RulePhase::After)
    end

    it "populates ctx.result before after rules run" do
      observed_result = nil
      service = TrackedService.new
      service.after(Alumna::Rule.new do |ctx|
        observed_result = ctx.result
        Alumna::RuleResult.continue
      end)

      dispatch(service, Alumna::ServiceMethod::Find)
      observed_result.should_not be_nil
    end

    it "runs error rules when before stops" do
      log = [] of String
      svc = TrackedService.new
      svc.before(stopping_rule("boom"))
      svc.error(Alumna::Rule.new { log << "error"; Alumna::RuleResult.continue })

      ctx = dispatch(svc, Alumna::ServiceMethod::Find)
      log.should eq(["error"])
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "runs app error rules when service errors" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      app.error(Alumna::Rule.new { log << "app-error"; Alumna::RuleResult.continue })
      app.use("/x", svc)

      ctx = make_ctx(app, svc, Alumna::ServiceMethod::Update, "999")
      app.dispatch(svc, ctx)

      log.should eq(["app-error"])
    end
  end

  describe "only: scoping" do
    it "runs a method-scoped rule only for its registered method" do
      log = [] of String
      service = TrackedService.new
      service.before(continuing_rule(log, "create-only"), only: [Alumna::ServiceMethod::Create])

      dispatch(service, Alumna::ServiceMethod::Find)
      log.should be_empty

      dispatch(service, Alumna::ServiceMethod::Create, nil, {"x" => "y"} of String => Alumna::AnyData)
      log.should eq(["create-only"])
    end

    it "does not run a method-scoped rule for any other method" do
      log = [] of String
      service = TrackedService.new
      service.after(continuing_rule(log, "find-after"), only: [Alumna::ServiceMethod::Find])

      dispatch(service, Alumna::ServiceMethod::Create, nil, {"x" => "y"} of String => Alumna::AnyData)
      log.should be_empty
    end
  end

  describe "global vs method-specific rules" do
    it "orders app-before, svc-before, svc-after, app-after" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      app.before(Alumna::Rule.new { log << "app-before"; Alumna::RuleResult.continue })
      app.after(Alumna::Rule.new { log << "app-after"; Alumna::RuleResult.continue })
      svc.before(Alumna::Rule.new { log << "svc-before"; Alumna::RuleResult.continue })
      svc.after(Alumna::Rule.new { log << "svc-after"; Alumna::RuleResult.continue })
      app.use("/ordered", svc)

      ctx = make_ctx(app, svc, Alumna::ServiceMethod::Find)
      app.dispatch(svc, ctx)

      log.should eq(["app-before", "svc-before", "svc-after", "app-after"])
    end

    it "skips service and app.after when app.before stops" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      app.before(Alumna::Rule.new { log << "app-before"; Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized) })
      svc.before(Alumna::Rule.new { log << "svc-before"; Alumna::RuleResult.continue })
      app.after(Alumna::Rule.new { log << "app-after"; Alumna::RuleResult.continue })
      app.use("/x", svc)

      ctx = make_ctx(app, svc, Alumna::ServiceMethod::Find)
      app.dispatch(svc, ctx)

      log.should eq(["app-before"])
      svc.called.should be_empty
    end

    it "skips service but still runs app.after when app.before sets result" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      app.before(Alumna::Rule.new { |c|
        c.result = {"cached" => true} of String => Alumna::AnyData
        log << "app-before"
        Alumna::RuleResult.continue
      })
      app.after(Alumna::Rule.new { log << "app-after"; Alumna::RuleResult.continue })
      app.use("/x", svc)

      ctx = make_ctx(app, svc, Alumna::ServiceMethod::Find)
      app.dispatch(svc, ctx)

      log.should eq(["app-before", "app-after"])
      svc.called.should be_empty
    end

    it "skips app.after when service errors" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      svc.before(stopping_rule("boom"))
      app.after(Alumna::Rule.new { log << "app-after"; Alumna::RuleResult.continue })
      app.use("/x", svc)

      ctx = make_ctx(app, svc, Alumna::ServiceMethod::Find)
      app.dispatch(svc, ctx)

      log.should be_empty
    end
  end

  describe "when a before rule stops" do
    it "does not call the service method" do
      service = TrackedService.new
      service.before(stopping_rule("blocked"))
      dispatch(service, Alumna::ServiceMethod::Find)
      service.called.should be_empty
    end

    it "does not run after rules" do
      log = [] of String
      service = TrackedService.new
      service.before(stopping_rule("blocked"))
      service.after(continuing_rule(log, "after"))
      dispatch(service, Alumna::ServiceMethod::Find)
      log.should be_empty
    end

    it "sets ctx.error to the error from the stopping rule" do
      service = TrackedService.new
      service.before(stopping_rule("no access"))
      ctx = dispatch(service, Alumna::ServiceMethod::Find)

      ctx.error.should_not be_nil
      error = ctx.error.as(Alumna::ServiceError)
      error.message.should eq("no access")
      error.status.should eq(401)
    end
  end

  describe "when a before rule sets ctx.result (early exit)" do
    it "does not call the service method" do
      service = TrackedService.new
      service.before(result_setting_rule("cached"))
      dispatch(service, Alumna::ServiceMethod::Find)
      service.called.should be_empty
    end

    it "run after rules even with result already set" do
      log = [] of String
      service = TrackedService.new
      service.before(result_setting_rule("cached"))
      service.after(continuing_rule(log, "after"))
      dispatch(service, Alumna::ServiceMethod::Find)
      log.should eq(["after"])
    end

    it "preserves the result set by the before rule" do
      service = TrackedService.new
      service.before(result_setting_rule("from-cache"))
      ctx = dispatch(service, Alumna::ServiceMethod::Find)
      ctx.result.as(Hash(String, Alumna::AnyData))["shortcut"].should eq("from-cache")
    end
  end

  describe "when the service method raises a ServiceError" do
    it "sets ctx.error with the correct status" do
      service = TrackedService.new
      ctx = dispatch(service, Alumna::ServiceMethod::Update, "999", {"x" => "y"} of String => Alumna::AnyData)

      ctx.error.should_not be_nil
      ctx.error.as(Alumna::ServiceError).status.should eq(404)
    end

    it "sets ctx.phase to Error" do
      service = TrackedService.new
      ctx = dispatch(service, Alumna::ServiceMethod::Update, "999", {"x" => "y"} of String => Alumna::AnyData)
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "does not run after rules" do
      log = [] of String
      service = TrackedService.new
      service.after(continuing_rule(log, "after"))
      dispatch(service, Alumna::ServiceMethod::Update, "999", {"x" => "y"} of String => Alumna::AnyData)
      log.should be_empty
    end
  end
end
