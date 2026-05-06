require "../spec_helper"

class DummyRuleable
  include Alumna::Ruleable
end

describe Alumna::Ruleable do
  rule = ->(_ctx : Alumna::RuleContext) : Alumna::ServiceError? { nil }

  it "registers global before rules" do
    r = DummyRuleable.new.before(rule)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "excludes global rules from OPTIONS by convention" do
    r = DummyRuleable.new.before(rule)
    r.collect_rules(Alumna::ServiceMethod::Options, Alumna::RulePhase::Before).size.should eq(0)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "registers specific after rules with symbols" do
    r = DummyRuleable.new.after(rule, on: [:create, :update])
    creates = r.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::After)
    finds = r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::After)
    creates.size.should eq(1)
    finds.size.should eq(0)
  end

  it "normalizes symbols to enums" do
    r = DummyRuleable.new.before(rule, on: :patch)
    r.collect_rules(Alumna::ServiceMethod::Patch, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "accepts single enum overload for before" do
    r = DummyRuleable.new
    r.before(rule, on: Alumna::ServiceMethod::Find)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "accepts single symbol and normalizes via capitalize" do
    r = DummyRuleable.new
    r.before(rule, on: :create)
    r.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "accepts uppercase symbol for after" do
    r = DummyRuleable.new
    r.after(rule, on: :FIND)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::After).size.should eq(1)
  end

  it "accepts array of symbols" do
    r = DummyRuleable.new
    r.before(rule, on: [:find, :create])
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
    r.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::Before).size.should eq(1)
    r.collect_rules(Alumna::ServiceMethod::Get, Alumna::RulePhase::Before).size.should eq(0)
  end

  it "runs global before specific" do
    r = DummyRuleable.new
    order = [] of String
    global = Alumna::Rule.new { |_ctx| order << "global"; nil.as(Alumna::ServiceError?) }
    specific = Alumna::Rule.new { |_ctx| order << "specific"; nil.as(Alumna::ServiceError?) }

    r.before(global)
    r.before(specific, on: :get)

    rules = r.collect_rules(Alumna::ServiceMethod::Get, Alumna::RulePhase::Before)
    Alumna::Orchestrator.run(rules, test_ctx(method: Alumna::ServiceMethod::Get))

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
    svc = Alumna::MemoryAdapter.new
    app.before(rule)
    svc.before(rule, on: :find)

    app.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
    svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
  end

  it "registers error rules" do
    r = DummyRuleable.new.error(rule)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Error).size.should eq(1)
  end

  it "accepts single enum overload for error" do
    r = DummyRuleable.new
    r.error(rule, on: Alumna::ServiceMethod::Find)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Error).size.should eq(1)
  end

  it "accepts single symbol for error and normalizes" do
    r = DummyRuleable.new
    r.error(rule, on: :create)
    r.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::Error).size.should eq(1)
  end

  it "registers before rules via block form" do
    r = DummyRuleable.new.before { |_ctx| nil }
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
    r.collect_rules(Alumna::ServiceMethod::Options, Alumna::RulePhase::Before).size.should eq(0)
  end

  it "registers after rules via block form with on: :write" do
    r = DummyRuleable.new.after(on: :write) { |_ctx| nil }
    r.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::After).size.should eq(1)
    r.collect_rules(Alumna::ServiceMethod::Update, Alumna::RulePhase::After).size.should eq(1)
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::After).size.should eq(0)
  end

  it "registers error rules via block form with on: :read" do
    r = DummyRuleable.new.error(on: :read) { |_ctx| nil }
    r.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Error).size.should eq(1)
    r.collect_rules(Alumna::ServiceMethod::Get, Alumna::RulePhase::Error).size.should eq(1)
    r.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::Error).size.should eq(0)
  end
end
