require "../spec_helper"
require "../../src/testing"

private class TrackedService < Alumna::MemoryAdapter
  getter called : Array(String)

  def initialize
    super()
    @called = [] of String
  end

  def find(ctx : Alumna::RuleContext) : Array(Hash(String, Alumna::AnyData)) | Alumna::ServiceError
    @called << "find"
    super
  end

  def create(ctx : Alumna::RuleContext) : Hash(String, Alumna::AnyData) | Alumna::ServiceError
    @called << "create"
    super
  end

  def update(ctx : Alumna::RuleContext) : Hash(String, Alumna::AnyData) | Alumna::ServiceError
    @called << "update"
    super
  end

  def remove(ctx : Alumna::RuleContext) : Nil | Alumna::ServiceError
    @called << "remove"
    super
  end
end

private def dispatch(service, method, id = nil, data = {} of String => Alumna::AnyData, app = nil)
  app ||= Alumna::App.new
  mount_path = "/tracked" # TrackedService is always mounted here in this spec
  app.use(mount_path, service) unless app.services.has_key?(mount_path)

  ctx = Alumna::Testing.build_ctx(
    app: app,
    service: service,
    path: mount_path,
    method: method,
    id: id,
    data: data
  )
  app.dispatch(service, ctx)
  ctx
end

private def continuing_rule(log, label)
  Alumna::Rule.new { |_ctx| log << label; nil }
end

private def stopping_rule(message : String) : Alumna::Rule
  Alumna::Rule.new { |_ctx| Alumna::ServiceError.unauthorized(message) }
end

private def result_setting_rule(label : String) : Alumna::Rule
  Alumna::Rule.new do |ctx|
    ctx.result = {"shortcut" => label} of String => Alumna::AnyData
    nil.as(Alumna::ServiceError?)
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
        nil
      end)

      dispatch(service, Alumna::ServiceMethod::Find)
      observed_phase.should eq(Alumna::RulePhase::After)
    end

    it "populates ctx.result before after rules run" do
      observed_result = nil
      service = TrackedService.new
      service.after(Alumna::Rule.new do |ctx|
        observed_result = ctx.result
        nil
      end)

      dispatch(service, Alumna::ServiceMethod::Find)
      observed_result.should_not be_nil
    end

    it "runs error rules when before stops" do
      log = [] of String
      svc = TrackedService.new
      svc.before(stopping_rule("boom"))
      svc.error(Alumna::Rule.new { log << "error"; nil })

      ctx = dispatch(svc, Alumna::ServiceMethod::Find)
      log.should eq(["error"])
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "runs app error rules when service errors" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      app.error(Alumna::Rule.new { log << "app-error"; nil })
      app.use("/x", svc)

      ctx = Alumna::Testing.build_ctx(app: app, service: svc, path: "/x", method: Alumna::ServiceMethod::Update, id: "999")
      app.dispatch(svc, ctx)

      log.should eq(["app-error"])
    end
  end

  describe "on: scoping" do
    it "runs a method-scoped rule only for its registered method" do
      log = [] of String
      service = TrackedService.new
      service.before(continuing_rule(log, "create-only"), on: [Alumna::ServiceMethod::Create])

      dispatch(service, Alumna::ServiceMethod::Find)
      log.should be_empty

      dispatch(service, Alumna::ServiceMethod::Create, nil, {"x" => "y"} of String => Alumna::AnyData)
      log.should eq(["create-only"])
    end

    it "does not run a method-scoped rule for any other method" do
      log = [] of String
      service = TrackedService.new
      service.after(continuing_rule(log, "find-after"), on: [Alumna::ServiceMethod::Find])

      dispatch(service, Alumna::ServiceMethod::Create, nil, {"x" => "y"} of String => Alumna::AnyData)
      log.should be_empty
    end
  end

  describe "global vs method-specific rules" do
    it "orders app-before, svc-before, svc-after, app-after" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      app.before(Alumna::Rule.new { log << "app-before"; nil })
      app.after(Alumna::Rule.new { log << "app-after"; nil })
      svc.before(Alumna::Rule.new { log << "svc-before"; nil })
      svc.after(Alumna::Rule.new { log << "svc-after"; nil })
      app.use("/ordered", svc)

      ctx = Alumna::Testing.build_ctx(app: app, service: svc, path: "/ordered", method: Alumna::ServiceMethod::Find)
      app.dispatch(svc, ctx)

      log.should eq(["app-before", "svc-before", "svc-after", "app-after"])
    end

    it "skips service and app.after when app.before stops" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      app.before(Alumna::Rule.new { log << "app-before"; Alumna::ServiceError.unauthorized })
      svc.before(Alumna::Rule.new { log << "svc-before"; nil })
      app.after(Alumna::Rule.new { log << "app-after"; nil })
      app.use("/x", svc)

      ctx = Alumna::Testing.build_ctx(app: app, service: svc, path: "/x", method: Alumna::ServiceMethod::Find)
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
        nil
      })
      app.after(Alumna::Rule.new { log << "app-after"; nil })
      app.use("/x", svc)

      ctx = Alumna::Testing.build_ctx(app: app, service: svc, path: "/x", method: Alumna::ServiceMethod::Find)
      app.dispatch(svc, ctx)

      log.should eq(["app-before", "app-after"])
      svc.called.should be_empty
    end

    it "skips app.after when service errors" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      svc.before(stopping_rule("boom"))
      app.after(Alumna::Rule.new { log << "app-after"; nil })
      app.use("/x", svc)

      ctx = Alumna::Testing.build_ctx(app: app, service: svc, path: "/x", method: Alumna::ServiceMethod::Find)
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

    it "short-circuits even if the result is explicitly set to nil" do
      service = TrackedService.new
      service.before(Alumna::Rule.new do |ctx|
        ctx.result = nil
        nil.as(Alumna::ServiceError?)
      end)
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

  describe "when a rule raises an Exception" do
    it "converts a before-rule raise into 500 and runs the error phase" do
      log = [] of String
      service = TrackedService.new
      service.before(Alumna::Rule.new { |_ctx| raise "rule boom" })
      service.error(Alumna::Rule.new { log << "error"; nil })

      ctx = dispatch(service, Alumna::ServiceMethod::Find)

      err = ctx.error
      err.should be_a(Alumna::ServiceError)
      if err
        err.status.should eq(500)
        err.message.should eq("rule boom")
      end
      ctx.phase.should eq(Alumna::RulePhase::Error)
      ctx.result_set?.should be_false
      log.should eq(["error"])
      service.called.should be_empty
    end

    it "converts an after-rule raise into 500" do
      service = TrackedService.new
      service.after(Alumna::Rule.new { |_ctx| raise "after boom" })

      ctx = dispatch(service, Alumna::ServiceMethod::Find)

      err = ctx.error
      err.should be_a(Alumna::ServiceError)
      if err
        err.status.should eq(500)
        err.message.should eq("after boom")
      end
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "keeps the first error when the error pipeline also raises" do
      service = TrackedService.new
      service.before(Alumna::Rule.new { |_ctx| raise "first" })
      service.error(Alumna::Rule.new { |_ctx| raise "second" })

      ctx = dispatch(service, Alumna::ServiceMethod::Find)

      err = ctx.error
      err.should be_a(Alumna::ServiceError)
      if err
        err.status.should eq(500)
        err.message.should eq("first")
      end
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "keeps a returned ServiceError when an error-rule raises" do
      service = TrackedService.new
      service.before(stopping_rule("no token"))
      service.error(Alumna::Rule.new { |_ctx| raise "error-rule boom" })

      ctx = dispatch(service, Alumna::ServiceMethod::Find)

      err = ctx.error
      err.should be_a(Alumna::ServiceError)
      if err
        err.status.should eq(401)
        err.message.should eq("no token")
      end
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end
  end

  describe "when the service method returns a ServiceError" do
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

  describe "after_commit" do
    it "runs service then app after_commit after after" do
      log = [] of String
      app = Alumna::App.new
      svc = TrackedService.new
      app.after(Alumna::Rule.new { log << "app-after"; nil })
      app.after_commit(Alumna::Rule.new { log << "app-ac"; nil })
      svc.after(Alumna::Rule.new { log << "svc-after"; nil })
      svc.after_commit(Alumna::Rule.new { log << "svc-ac"; nil })
      app.use("/ordered", svc)

      ctx = Alumna::Testing.build_ctx(app: app, service: svc, path: "/ordered", method: Alumna::ServiceMethod::Find)
      app.dispatch(svc, ctx)

      log.should eq(["svc-after", "app-after", "svc-ac", "app-ac"])
      ctx.phase.should eq(Alumna::RulePhase::AfterCommit)
      ctx.error.should be_nil
    end

    it "skips after_commit when a before-rule sets ctx.result" do
      log = [] of String
      service = TrackedService.new
      service.before(result_setting_rule("cached"))
      service.after(continuing_rule(log, "after"))
      service.after_commit(continuing_rule(log, "ac"))
      dispatch(service, Alumna::ServiceMethod::Find)
      log.should eq(["after"])
      service.called.should be_empty
    end

    it "skips after_commit when before stops" do
      log = [] of String
      service = TrackedService.new
      service.before(stopping_rule("blocked"))
      service.after_commit(continuing_rule(log, "ac"))
      dispatch(service, Alumna::ServiceMethod::Find)
      log.should be_empty
    end

    it "skips after_commit when the service method returns a ServiceError" do
      log = [] of String
      service = TrackedService.new
      service.after_commit(continuing_rule(log, "ac"))
      dispatch(service, Alumna::ServiceMethod::Update, "999", {"x" => "y"} of String => Alumna::AnyData)
      log.should be_empty
    end

    it "skips after_commit when after returns a ServiceError" do
      log = [] of String
      service = TrackedService.new
      service.after(stopping_rule("after-fail"))
      service.after_commit(continuing_rule(log, "ac"))
      ctx = dispatch(service, Alumna::ServiceMethod::Find)
      log.should be_empty
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "runs after_commit on a successful remove with a nil result" do
      log = [] of String
      service = TrackedService.new
      service.after_commit(continuing_rule(log, "ac"), on: :mutate)
      created = dispatch(service, Alumna::ServiceMethod::Create, nil, {"x" => "y"} of String => Alumna::AnyData)
      id = created.result.as(Hash(String, Alumna::AnyData))["id"].as(String)
      log.clear
      ctx = dispatch(service, Alumna::ServiceMethod::Remove, id)
      log.should eq(["ac"])
      service.called.should contain("remove")
      ctx.result.should be_nil
      ctx.error.should be_nil
      ctx.phase.should eq(Alumna::RulePhase::AfterCommit)
    end

    it "does not run on: :mutate after_commit for find" do
      log = [] of String
      service = TrackedService.new
      service.after_commit(continuing_rule(log, "ac"), on: :mutate)
      dispatch(service, Alumna::ServiceMethod::Find)
      log.should be_empty
    end

    it "runs the error pipeline when after_commit returns a ServiceError" do
      log = [] of String
      service = TrackedService.new
      service.after_commit(stopping_rule("ac-fail"))
      service.error(Alumna::Rule.new { log << "error"; nil })
      ctx = dispatch(service, Alumna::ServiceMethod::Create, nil, {"x" => "y"} of String => Alumna::AnyData)

      log.should eq(["error"])
      ctx.phase.should eq(Alumna::RulePhase::Error)
      err = ctx.error
      err.should be_a(Alumna::ServiceError)
      if err
        err.status.should eq(401)
        err.message.should eq("ac-fail")
      end
      ctx.result_set?.should be_true
    end

    it "converts an after_commit raise into 500" do
      service = TrackedService.new
      service.after_commit(Alumna::Rule.new { |_ctx| raise "ac boom" })
      ctx = dispatch(service, Alumna::ServiceMethod::Find)

      err = ctx.error
      err.should be_a(Alumna::ServiceError)
      if err
        err.status.should eq(500)
        err.message.should eq("ac boom")
      end
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "allows ctx.call from after_commit; nested dispatch has its own after_commit" do
      nested = [] of String
      app = Alumna::App.new
      inner = Alumna::MemoryAdapter.new
      outer = Alumna::MemoryAdapter.new
      inner.after_commit(Alumna::Rule.new { nested << "inner-ac"; nil })
      outer.after_commit(Alumna::Rule.new { |c|
        nested << "outer-ac"
        c.call("/inner", :create, Alumna.hash(n: "i"))
        nil
      })
      app.use("/inner", inner)
      app.use("/outer", outer)

      ctx = Alumna::Testing.build_ctx(
        app: app,
        service: outer,
        path: "/outer",
        method: Alumna::ServiceMethod::Create,
        data: Alumna.hash(n: "o")
      )
      app.dispatch(outer, ctx)

      nested.should eq(["outer-ac", "inner-ac"])
      ctx.error.should be_nil
    end

    it "runs after_commit for the websocket provider" do
      log = [] of String
      app = Alumna::App.new
      svc = Alumna::MemoryAdapter.new
      app.after_commit(Alumna::Rule.new { log << "ac"; nil })
      app.use("/items", svc)
      session = Alumna::Http::WebSocketSession.new(
        HTTP::WebSocket.new(IO::Memory.new),
        HTTP::Headers.new,
        "127.0.0.1",
        app,
      )
      reply = session.process_frame(%({"id":"1","method":"create","path":"/items","data":{"name":"a"}}))
      reply["result"].as(Hash)["name"].should eq("a")
      log.should eq(["ac"])
    end
  end
end
