require "../spec_helper"

# ── Test doubles ──────────────────────────────────────────────────────────────

# TrackedService wraps MemoryAdapter and records which service methods are
# actually invoked by dispatch. This lets specs assert that the service method
# was (or was not) called without inspecting side-effects on the store.
private class TrackedService < Alumna::MemoryAdapter
  getter called : Array(String)

  def initialize
    super("/tracked")
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

# ── Helpers ───────────────────────────────────────────────────────────────────

# Builds a RuleContext for a given service and method.
private def make_ctx(
  service : Alumna::Service,
  method : Alumna::ServiceMethod,
  id : String? = nil,
  data : Hash(String, Alumna::AnyData) = {} of String => Alumna::AnyData,
) : Alumna::RuleContext
  Alumna::RuleContext.new(
    app: Alumna::App.new,
    service: service,
    path: service.path,
    method: method,
    phase: Alumna::RulePhase::Before,
    id: id,
    data: data
  )
end

# Rule factories — identical in spirit to the orchestrator spec helpers,
# defined locally here so this spec file has no hidden dependencies.

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

# ─────────────────────────────────────────────────────────────────────────────

describe "Service#dispatch" do
  # ── Execution order: before → service method → after ─────────────────────────

  describe "execution order" do
    it "runs before rules, then the service method, then after rules" do
      log = [] of String
      service = TrackedService.new

      service.before(continuing_rule(log, "before-1"))
      service.before(continuing_rule(log, "before-2"))
      service.after(continuing_rule(log, "after-1"))

      ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(ctx)

      # Before rules must precede the service call;
      # service call is confirmed by TrackedService#called;
      # after rules must follow.
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

      ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(ctx)

      observed_phase.should eq(Alumna::RulePhase::After)
    end

    it "populates ctx.result before after rules run" do
      observed_result = nil

      service = TrackedService.new
      service.after(Alumna::Rule.new do |ctx|
        observed_result = ctx.result
        Alumna::RuleResult.continue
      end)

      ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(ctx)

      # find on an empty store returns [] — result must be set (not nil)
      observed_result.should_not be_nil
    end

    it "runs error rules when before stops" do
      log = [] of String
      svc = TrackedService.new
      svc.before(stopping_rule("boom"))
      svc.error(Alumna::Rule.new { log << "error"; Alumna::RuleResult.continue })

      ctx = make_ctx(svc, Alumna::ServiceMethod::Find)
      svc.dispatch(ctx)

      log.should eq(["error"])
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "runs app error rules when service errors" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new

      app.error(Alumna::Rule.new { log << "app-error"; Alumna::RuleResult.continue })
      app.use("/x", svc)

      ctx = Alumna::RuleContext.new(app: app, service: svc, path: "/x", method: Alumna::ServiceMethod::Update, phase: Alumna::RulePhase::Before, id: "999")
      app.dispatch(svc, ctx)

      log.should eq(["app-error"])
    end
  end

  # ── only: scoping ─────────────────────────────────────────────────────────────

  describe "only: scoping" do
    it "runs a method-scoped rule only for its registered method" do
      log = [] of String
      service = TrackedService.new

      service.before(
        continuing_rule(log, "create-only"),
        only: [Alumna::ServiceMethod::Create]
      )

      # Find should NOT trigger the create-only rule
      find_ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(find_ctx)
      log.should be_empty

      # Create SHOULD trigger it
      create_ctx = make_ctx(service, Alumna::ServiceMethod::Create, data: {"x" => "y"} of String => Alumna::AnyData)
      service.dispatch(create_ctx)
      log.should eq(["create-only"])
    end

    it "does not run a method-scoped rule for any other method" do
      log = [] of String
      service = TrackedService.new

      service.after(
        continuing_rule(log, "find-after"),
        only: [Alumna::ServiceMethod::Find]
      )

      # Create should NOT trigger the find-scoped after rule
      create_ctx = make_ctx(service, Alumna::ServiceMethod::Create, data: {"x" => "y"} of String => Alumna::AnyData)
      service.dispatch(create_ctx)
      log.should be_empty
    end
  end

  # ── Global vs method-specific rules ───────────────────────────────────────

  describe "global vs method-specific rules" do
    it "runs app rules around service rules" do
      log = [] of String

      app = Alumna::App.new
      svc = Alumna::MemoryAdapter.new("/ordered")

      app.before(Alumna::Rule.new { log << "app-before"; Alumna::RuleResult.continue })
      app.after(Alumna::Rule.new { log << "app-after"; Alumna::RuleResult.continue })

      svc.before(Alumna::Rule.new { log << "svc-before"; Alumna::RuleResult.continue })
      svc.after(Alumna::Rule.new { log << "svc-after"; Alumna::RuleResult.continue })

      app.use("/ordered", svc)

      ctx = Alumna::RuleContext.new(
        app: app,
        service: svc,
        path: "/ordered",
        method: Alumna::ServiceMethod::Find,
        phase: Alumna::RulePhase::Before
      )

      app.dispatch(svc, ctx) # use the new App#dispatch, not svc.dispatch

      log.should eq(["app-before", "svc-before", "svc-after", "app-after"])
    end

    it "skips service and app.after when app.before stops" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new

      app.before(Alumna::Rule.new { log << "app-before"; Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized) })
      svc.before(Alumna::Rule.new { log << "svc-before"; Alumna::RuleResult.continue })
      app.after(Alumna::Rule.new { log << "app-after"; Alumna::RuleResult.continue })

      ctx = make_ctx(svc, Alumna::ServiceMethod::Find)
      ctx = Alumna::RuleContext.new(app: app, service: svc, path: "/x", method: Alumna::ServiceMethod::Find, phase: Alumna::RulePhase::Before)

      app.dispatch(svc, ctx)
      log.should eq(["app-before"])
      svc.called.should be_empty
    end

    it "skips service but still runs app.after when app.before sets result" do
      # this documents current behavior: result_set stops service, not app.after
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new

      app.before(Alumna::Rule.new { |c|
        c.result = {"cached" => true} of String => Alumna::AnyData
        log << "app-before"
        Alumna::RuleResult.continue
      })
      app.after(Alumna::Rule.new { log << "app-after"; Alumna::RuleResult.continue })

      ctx = Alumna::RuleContext.new(app: app, service: svc, path: "/x", method: Alumna::ServiceMethod::Find, phase: Alumna::RulePhase::Before)
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

      ctx = make_ctx(svc, Alumna::ServiceMethod::Find)
      ctx = Alumna::RuleContext.new(app: app, service: svc, path: "/x", method: Alumna::ServiceMethod::Find, phase: Alumna::RulePhase::Before)

      app.dispatch(svc, ctx)
      log.should be_empty
    end
  end

  # ── Before rule stops: service method and after rules are skipped ─────────────

  describe "when a before rule stops" do
    it "does not call the service method" do
      service = TrackedService.new
      service.before(stopping_rule("blocked"))

      ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(ctx)

      service.called.should be_empty
    end

    it "does not run after rules" do
      log = [] of String
      service = TrackedService.new

      service.before(stopping_rule("blocked"))
      service.after(continuing_rule(log, "after"))

      ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(ctx)

      log.should be_empty
    end

    it "sets ctx.error to the error from the stopping rule" do
      service = TrackedService.new
      service.before(stopping_rule("no access"))

      ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(ctx)

      error = ctx.error
      error.should_not be_nil
      if error
        error.message.should eq("no access")
        error.status.should eq(401)
      end
    end
  end

  # ── Before rule sets result: service method and after rules are skipped ───────

  describe "when a before rule sets ctx.result (early exit)" do
    it "does not call the service method" do
      service = TrackedService.new
      service.before(result_setting_rule("cached"))

      ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(ctx)

      service.called.should be_empty
    end

    it "run after rules even with result already set" do
      log = [] of String
      service = TrackedService.new

      service.before(result_setting_rule("cached"))
      service.after(continuing_rule(log, "after"))

      ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(ctx)

      log.should eq(["after"])
    end

    it "preserves the result set by the before rule" do
      service = TrackedService.new
      service.before(result_setting_rule("from-cache"))

      ctx = make_ctx(service, Alumna::ServiceMethod::Find)
      service.dispatch(ctx)

      result = ctx.result.as(Hash(String, Alumna::AnyData))
      result["shortcut"].should eq("from-cache")
    end
  end

  # ── Service method raises: after rules are skipped ────────────────────────────

  describe "when the service method raises a ServiceError" do
    it "sets ctx.error with the correct status" do
      service = TrackedService.new

      # update on a non-existent id raises a 404 from MemoryAdapter
      ctx = make_ctx(service, Alumna::ServiceMethod::Update, id: "999", data: {"x" => "y"} of String => Alumna::AnyData)
      service.dispatch(ctx)

      error = ctx.error
      error.should_not be_nil
      if error
        error.status.should eq(404)
      end
    end

    it "sets ctx.phase to Error" do
      service = TrackedService.new
      ctx = make_ctx(service, Alumna::ServiceMethod::Update, id: "999", data: {"x" => "y"} of String => Alumna::AnyData)
      service.dispatch(ctx)

      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "does not run after rules" do
      log = [] of String
      service = TrackedService.new
      service.after(continuing_rule(log, "after"))

      ctx = make_ctx(service, Alumna::ServiceMethod::Update, id: "999", data: {"x" => "y"} of String => Alumna::AnyData)
      service.dispatch(ctx)

      log.should be_empty
    end
  end
end
