require "../spec_helper"

private def dummy_ctx : Alumna::RuleContext
  app = Alumna::App.new
  service = Alumna::MemoryAdapter.new("/dummy")
  Alumna::RuleContext.new(
    app: app,
    service: service,
    path: "/dummy",
    method: Alumna::ServiceMethod::Find,
    phase: Alumna::RulePhase::Before
  )
end

# proves the alias is structural, not tied to a specific literal
def my_rule(ctx : Alumna::RuleContext) : Alumna::RuleResult
  Alumna::RuleResult.continue
end

describe Alumna::RuleResult do
  describe ".continue" do
    it "creates a Continue result with no error" do
      result = Alumna::RuleResult.continue

      result.outcome.should eq(Alumna::RuleResult::Outcome::Continue)
      result.error.should be_nil
      result.continue?.should be_true
      result.stop?.should be_false
    end
  end

  describe ".stop" do
    it "creates a Stop result with the given error" do
      err = Alumna::ServiceError.unauthorized("nope")
      result = Alumna::RuleResult.stop(err)

      result.outcome.should eq(Alumna::RuleResult::Outcome::Stop)
      result.error.should be(err)
      result.error.not_nil!.status.should eq(401)
      result.continue?.should be_false
      result.stop?.should be_true
    end
  end

  describe "Outcome enum" do
    it "exposes Continue and Stop" do
      Alumna::RuleResult::Outcome::Continue.should eq(Alumna::RuleResult::Outcome::Continue)
      Alumna::RuleResult::Outcome::Stop.continue?.should be_false
      Alumna::RuleResult::Outcome::Continue.stop?.should be_false
    end
  end
end

describe "Alumna::Rule alias" do
  it "accepts a Proc that takes RuleContext and returns RuleResult" do
    rule : Alumna::Rule = ->(ctx : Alumna::RuleContext) {
      ctx.headers["x"] = "1"
      Alumna::RuleResult.continue
    }

    ctx = dummy_ctx
    result = rule.call(ctx)

    result.should be_a(Alumna::RuleResult)
    result.continue?.should be_true
    ctx.headers["x"].should eq("1")
  end

  it "works with Rule.new shorthand" do
    rule = Alumna::Rule.new { |ctx| Alumna::RuleResult.stop(Alumna::ServiceError.forbidden) }

    result = rule.call(dummy_ctx)
    result.stop?.should be_true
    result.error.not_nil!.status.should eq(403)
  end

  it "works with a captured method" do
    rule : Alumna::Rule = ->my_rule(Alumna::RuleContext)
    rule.call(dummy_ctx).continue?.should be_true
  end
end
