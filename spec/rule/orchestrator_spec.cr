require "../spec_helper"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Builds the minimal RuleContext the orchestrator needs.
# Phase defaults to Before; pass Alumna::RulePhase::After to test after-rules.
private def make_ctx(phase : Alumna::RulePhase = Alumna::RulePhase::Before) : Alumna::RuleContext
  app = Alumna::App.new
  service = Alumna::MemoryAdapter.new("/test")
  Alumna::RuleContext.new(
    app: app,
    service: service,
    path: "/test",
    method: Alumna::ServiceMethod::Find,
    phase: phase
  )
end

# A rule that appends `label` to `log` and continues.
private def continuing_rule(log : Array(String), label : String) : Alumna::Rule
  Alumna::Rule.new do |ctx|
    log << label
    Alumna::RuleResult.continue
  end
end

# A rule that appends `label` to `log` and stops with a bad-request error.
private def stopping_rule(log : Array(String), label : String, message : String = "stopped") : Alumna::Rule
  Alumna::Rule.new do |ctx|
    log << label
    Alumna::RuleResult.stop(Alumna::ServiceError.bad_request(message))
  end
end

# A rule that appends `label`, sets ctx.result, then returns continue.
# Simulates a before-rule short-circuiting the service call (e.g. a cache hit).
private def result_setting_rule(log : Array(String), label : String) : Alumna::Rule
  Alumna::Rule.new do |ctx|
    log << label
    ctx.result = {"cached" => Alumna::AnyData.new(true)}
    Alumna::RuleResult.continue
  end
end

# ─────────────────────────────────────────────────────────────────────────────

describe Alumna::Orchestrator do
  # ── Empty rule list ──────────────────────────────────────────────────────────

  describe "with an empty rule list" do
    it "returns the context unchanged" do
      ctx = make_ctx
      Alumna::Orchestrator.new([] of Alumna::Rule).run(ctx)
      ctx.error.should be_nil
      ctx.phase.should eq(Alumna::RulePhase::Before)
    end
  end

  # ── All rules continue ───────────────────────────────────────────────────────

  describe "when all rules return continue" do
    it "calls every rule in registration order" do
      log = [] of String
      rules = [
        continuing_rule(log, "a"),
        continuing_rule(log, "b"),
        continuing_rule(log, "c"),
      ]
      Alumna::Orchestrator.new(rules).run(make_ctx)
      log.should eq(["a", "b", "c"])
    end

    it "leaves ctx.error nil" do
      log = [] of String
      rules = [continuing_rule(log, "a"), continuing_rule(log, "b")]
      ctx = make_ctx
      Alumna::Orchestrator.new(rules).run(ctx)
      ctx.error.should be_nil
    end

    it "leaves ctx.phase unchanged" do
      rules = [continuing_rule([] of String, "a")]
      ctx = make_ctx(Alumna::RulePhase::Before)
      Alumna::Orchestrator.new(rules).run(ctx)
      ctx.phase.should eq(Alumna::RulePhase::Before)
    end
  end

  # ── Stop ─────────────────────────────────────────────────────────────────────

  describe "when a rule returns stop" do
    it "sets ctx.error to the ServiceError carried by the result" do
      rule = Alumna::Rule.new do |ctx|
        Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized("no token"))
      end
      ctx = make_ctx
      Alumna::Orchestrator.new([rule]).run(ctx)
      ctx.error.not_nil!.message.should eq("no token")
      ctx.error.not_nil!.status.should eq(401)
    end

    it "sets ctx.phase to Error" do
      rule = Alumna::Rule.new { |ctx| Alumna::RuleResult.stop(Alumna::ServiceError.forbidden) }
      ctx = make_ctx
      Alumna::Orchestrator.new([rule]).run(ctx)
      ctx.phase.should eq(Alumna::RulePhase::Error)
    end

    it "does not call any rule registered after the stopping rule" do
      log = [] of String
      rules = [
        continuing_rule(log, "before"),
        stopping_rule(log, "stopper"),
        continuing_rule(log, "after"),
      ]
      Alumna::Orchestrator.new(rules).run(make_ctx)
      log.should eq(["before", "stopper"])
      log.should_not contain("after")
    end

    it "calls every rule registered before the stopping rule" do
      log = [] of String
      rules = [
        continuing_rule(log, "a"),
        continuing_rule(log, "b"),
        stopping_rule(log, "c"),
        continuing_rule(log, "d"),
      ]
      Alumna::Orchestrator.new(rules).run(make_ctx)
      log.should eq(["a", "b", "c"])
    end

    it "uses the first stop when multiple rules would stop" do
      log = [] of String
      rules = [
        stopping_rule(log, "first", "error-one"),
        stopping_rule(log, "second", "error-two"),
      ]
      ctx = make_ctx
      Alumna::Orchestrator.new(rules).run(ctx)
      ctx.error.not_nil!.message.should eq("error-one")
      log.should eq(["first"])
    end
  end

  # ── Early exit when result is set in Before phase ────────────────────────────

  describe "early exit when ctx.result is set during Before phase" do
    it "stops processing further rules once a rule sets ctx.result" do
      log = [] of String
      rules = [
        continuing_rule(log, "a"),
        result_setting_rule(log, "b"),
        continuing_rule(log, "c"),
      ]
      Alumna::Orchestrator.new(rules).run(make_ctx(Alumna::RulePhase::Before))
      log.should eq(["a", "b"])
      log.should_not contain("c")
    end

    it "does not set ctx.error when exiting early via result" do
      rules = [result_setting_rule([] of String, "r")]
      ctx = make_ctx(Alumna::RulePhase::Before)
      Alumna::Orchestrator.new(rules).run(ctx)
      ctx.error.should be_nil
    end

    it "preserves the result value set by the rule" do
      rules = [result_setting_rule([] of String, "r")]
      ctx = make_ctx(Alumna::RulePhase::Before)
      Alumna::Orchestrator.new(rules).run(ctx)
      ctx.result_set?.should be_true
    end
  end

  # ── Early exit does NOT trigger in After phase ───────────────────────────────

  describe "early exit does not apply during After phase" do
    it "continues processing all rules even when ctx.result is set" do
      log = [] of String
      rules = [
        result_setting_rule(log, "a"),
        continuing_rule(log, "b"),
        continuing_rule(log, "c"),
      ]
      Alumna::Orchestrator.new(rules).run(make_ctx(Alumna::RulePhase::After))
      log.should eq(["a", "b", "c"])
    end
  end
end
