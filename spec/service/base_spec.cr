require "../spec_helper"

# ── Test doubles ──────────────────────────────────────────────────────────────

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
end

# Service that raises plain Exceptions, not ServiceError
private class ExplodingService < Alumna::Service
  def initialize
    super("/boom")
  end

  def find(ctx : Alumna::RuleContext) : Array(Hash(String, Alumna::AnyData))
    raise "kaboom"
  end

  def get(ctx : Alumna::RuleContext) : Hash(String, Alumna::AnyData)?
    raise Exception.new # message is nil
  end

  def create(ctx : Alumna::RuleContext) : Hash(String, Alumna::AnyData)
    {} of String => Alumna::AnyData
  end

  def update(ctx : Alumna::RuleContext) : Hash(String, Alumna::AnyData)
    {} of String => Alumna::AnyData
  end

  def patch(ctx : Alumna::RuleContext) : Hash(String, Alumna::AnyData)
    {} of String => Alumna::AnyData
  end

  def remove(ctx : Alumna::RuleContext) : Bool
    true
  end
end

private def make_ctx(service : Alumna::Service, method : Alumna::ServiceMethod) : Alumna::RuleContext
  Alumna::RuleContext.new(
    app: Alumna::App.new,
    service: service,
    path: service.path,
    method: method,
    phase: Alumna::RulePhase::Before
  )
end

private def rule(log : Array(String), label : String) : Alumna::Rule
  Alumna::Rule.new do |ctx|
    log << label
    Alumna::RuleResult.continue
  end
end

describe "Service::Base" do
  describe "error boundary in call_method" do
    it "wraps a raised Exception with message into 500 (line 96)" do
      svc = ExplodingService.new
      ctx = make_ctx(svc, Alumna::ServiceMethod::Find)

      svc.dispatch(ctx)

      ctx.error.should_not be_nil
      err = ctx.error.not_nil!
      err.status.should eq(500)
      err.message.should eq("kaboom")
      ctx.phase.should eq(Alumna::RulePhase::Error)
      ctx.result_set?.should be_false
    end

    it "uses 'Unexpected error' when Exception.message is nil" do
      svc = ExplodingService.new
      ctx = make_ctx(svc, Alumna::ServiceMethod::Get)

      svc.dispatch(ctx)

      ctx.error.not_nil!.message.should eq("Unexpected error")
    end
  end
end
