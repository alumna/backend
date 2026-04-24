require "../spec_helper"

class DummyRuleable
  include Alumna::Ruleable
end

private def dummy_context : Alumna::RuleContext
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

describe Alumna::Ruleable do
  rule = ->(ctx : Alumna::RuleContext) { Alumna::RuleResult.continue }

  it "registers global before rules" do
    r = DummyRuleable.new.before(rule)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "registers specific after rules with symbols" do
    r = DummyRuleable.new.after(rule, only: [:create, :update])
    creates = r.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::After)
    finds = r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::After)
    creates.size.should eq(1)
    finds.size.should eq(0)
  end

  it "normalizes symbols to enums" do
    r = DummyRuleable.new.before(rule, only: :patch)
    r.collect_rules(Alumna::ServiceMethod::Patch, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "accepts single enum overload for before" do
    r = DummyRuleable.new
    r.before(rule, only: Alumna::ServiceMethod::Find)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "accepts single symbol and normalizes via capitalize" do
    r = DummyRuleable.new
    r.before(rule, only: :create)
    r.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "accepts uppercase symbol for after" do
    r = DummyRuleable.new
    r.after(rule, only: :FIND)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::After).size.should eq(1)
  end

  it "accepts array of symbols" do
    r = DummyRuleable.new
    r.before(rule, only: [:find, :create])
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
    r.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::Before).size.should eq(1)
    r.collect_rules(Alumna::ServiceMethod::Get, Alumna::RulePhase::Before).size.should eq(0)
  end

  it "runs global before specific" do
    r = DummyRuleable.new
    order = [] of String
    global = Alumna::Rule.new { order << "global"; Alumna::RuleResult.continue }
    specific = Alumna::Rule.new { order << "specific"; Alumna::RuleResult.continue }

    r.before(global)
    r.before(specific, only: :get)

    rules = r.collect_rules(Alumna::ServiceMethod::Get, Alumna::RulePhase::Before)
    Alumna::Orchestrator.run(rules, dummy_context)

    order.should eq(["global", "specific"])
  end

  it "preserves insertion order" do
    r = DummyRuleable.new
    r.before(rule).before(rule).after(rule)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(2)
  end

  it "returns self for chaining" do
    r = DummyRuleable.new
    (r.before(rule).after(rule)).should be(r)
  end

  it "works identically in App and Service" do
    app = Alumna::App.new
    svc = Alumna::MemoryAdapter.new("/test")
    app.before(rule)
    svc.before(rule, only: :find)

    app.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
    svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
  end
end
