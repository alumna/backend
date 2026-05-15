require "../spec_helper"
require "../../src/testing"

# ── Helpers ───────────────────────────────────

private def continuing_rule(log, label)
  Alumna::Rule.new { |_ctx| log << label; nil }
end

private def stopping_rule(log, label, message = "stopped")
  Alumna::Rule.new { |_ctx| log << label; Alumna::ServiceError.bad_request(message) }
end

private def result_setting_rule(log : Array(String), label : String) : Alumna::Rule
  Alumna::Rule.new do |ctx|
    log << label
    ctx.result = {"cached" => true} of String => Alumna::AnyData
    nil.as(Alumna::ServiceError?)
  end
end

# ─────────────────────────────────────────────────────────────────────────────

describe Alumna::Orchestrator do
  describe ".run with start parameter" do
    it "starts execution from the given index" do
      log = [] of String
      rules = [
        continuing_rule(log, "a"),
        continuing_rule(log, "b"),
        continuing_rule(log, "c"),
      ]

      result = Alumna::Orchestrator.run(rules, Alumna::Testing.build_ctx, start: 1)

      result.should be_true
      log.should eq(["b", "c"])
    end
  end

  describe ".run with empty rule list" do
    it "returns true and leaves context unchanged" do
      ctx = Alumna::Testing.build_ctx
      result = Alumna::Orchestrator.run([] of Alumna::Rule, ctx)

      result.should be_true
      ctx.error.should be_nil
      ctx.phase.should eq(Alumna::RulePhase::Before)
    end
  end

  describe "when all rules return continue" do
    it "calls every rule in registration order" do
      log = [] of String
      rules = [
        continuing_rule(log, "a"),
        continuing_rule(log, "b"),
        continuing_rule(log, "c"),
      ]

      result = Alumna::Orchestrator.run(rules, Alumna::Testing.build_ctx)

      result.should be_true
      log.should eq(["a", "b", "c"])
    end

    it "leaves ctx.error nil" do
      ctx = Alumna::Testing.build_ctx
      rules = [continuing_rule([] of String, "a")]

      Alumna::Orchestrator.run(rules, ctx)

      ctx.error.should be_nil
    end

    it "leaves ctx.phase unchanged" do
      ctx = Alumna::Testing.build_ctx(phase: Alumna::RulePhase::Before)

      Alumna::Orchestrator.run([continuing_rule([] of String, "a")], ctx)

      ctx.phase.should eq(Alumna::RulePhase::Before)
    end
  end

  describe "when a rule returns stop" do
    it "sets ctx.error to the ServiceError" do
      rule = Alumna::Rule.new { |_ctx| Alumna::ServiceError.unauthorized("no token") }
      ctx = Alumna::Testing.build_ctx

      Alumna::Orchestrator.run([rule], ctx)

      error = ctx.error
      error.should_not be_nil
      if error
        error.message.should eq("no token")
        error.status.should eq(401)
      end
    end

    it "returns false and does not change ctx.phase" do
      rule = Alumna::Rule.new { |_ctx| Alumna::ServiceError.forbidden }
      ctx = Alumna::Testing.build_ctx(phase: Alumna::RulePhase::Before)

      result = Alumna::Orchestrator.run([rule], ctx)

      result.should be_false
      ctx.phase.should eq(Alumna::RulePhase::Before)
    end

    it "does not call rules after the stopping rule" do
      log = [] of String
      rules = [
        continuing_rule(log, "before"),
        stopping_rule(log, "stopper"),
        continuing_rule(log, "after"),
      ]

      Alumna::Orchestrator.run(rules, Alumna::Testing.build_ctx)

      log.should eq(["before", "stopper"])
    end

    it "uses the first stop error" do
      log = [] of String
      rules = [
        stopping_rule(log, "first", "error-one"),
        stopping_rule(log, "second", "error-two"),
      ]
      ctx = Alumna::Testing.build_ctx

      Alumna::Orchestrator.run(rules, ctx)

      error = ctx.error
      error.should_not be_nil
      if error
        error.message.should eq("error-one")
      end
      log.should eq(["first"])
    end
  end

  describe "early exit when ctx.result is set in Before phase" do
    it "stops processing further before-rules when short_circuit is true" do
      log = [] of String
      rules = [
        continuing_rule(log, "a"),
        result_setting_rule(log, "b"),
        continuing_rule(log, "c"),
      ]

      Alumna::Orchestrator.run(rules, Alumna::Testing.build_ctx(phase: Alumna::RulePhase::Before), short_circuit: true)

      log.should eq(["a", "b"])
    end

    it "does not set ctx.error" do
      ctx = Alumna::Testing.build_ctx(phase: Alumna::RulePhase::Before)

      Alumna::Orchestrator.run([result_setting_rule([] of String, "r")], ctx, short_circuit: true)

      ctx.error.should be_nil
    end

    it "preserves the result" do
      ctx = Alumna::Testing.build_ctx(phase: Alumna::RulePhase::Before)

      Alumna::Orchestrator.run([result_setting_rule([] of String, "r")], ctx, short_circuit: true)

      ctx.result_set?.should be_true
      ctx.result.as(Hash(String, Alumna::AnyData))["cached"].should eq(true)
    end

    it "short-circuits even if the result is explicitly set to nil" do
      rule = Alumna::Rule.new do |ctx|
        ctx.result = nil
        nil.as(Alumna::ServiceError?)
      end
      ctx = Alumna::Testing.build_ctx(phase: Alumna::RulePhase::Before)

      Alumna::Orchestrator.run([rule], ctx, short_circuit: true)

      ctx.result_set?.should be_true
      ctx.result.should be_nil
    end
  end

  describe "early exit does not apply in After phase" do
    it "continues through all rules even when result is set and short_circuit is false" do
      log = [] of String
      rules = [
        result_setting_rule(log, "a"),
        continuing_rule(log, "b"),
        continuing_rule(log, "c"),
      ]

      Alumna::Orchestrator.run(rules, Alumna::Testing.build_ctx(phase: Alumna::RulePhase::After), short_circuit: false)

      log.should eq(["a", "b", "c"])
    end
  end

  describe "service errors are skipped when the app stops early" do
    it "skips service error hooks when app before-rule stops" do
      log = [] of String
      app = Alumna::App.new
      app.before(Alumna::Rule.new { |_ctx| log << "app-before"; Alumna::ServiceError.forbidden })
      app.error(Alumna::Rule.new { |_ctx| log << "app-error"; nil })

      svc = Alumna::MemoryAdapter.new
      svc.error(Alumna::Rule.new { |_ctx| log << "svc-error"; nil })
      app.use("/x", svc)

      ctx = Alumna::Testing.build_ctx(app: app, service: svc, method: Alumna::ServiceMethod::Find)
      app.dispatch(svc, ctx)

      log.should eq(["app-before", "app-error"]) # svc-error must NOT appear
    end
  end
end
