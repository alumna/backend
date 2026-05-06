require "../spec_helper"

private class ExplodingService < Alumna::Service
  def initialize
    super()
  end

  def find(ctx) : Array(Hash(String, Alumna::AnyData))
    raise "kaboom"
  end

  def get(ctx) : Hash(String, Alumna::AnyData)?
    raise Exception.new
  end

  def create(ctx) : Hash(String, Alumna::AnyData)
    {} of String => Alumna::AnyData
  end

  def update(ctx) : Hash(String, Alumna::AnyData)
    {} of String => Alumna::AnyData
  end

  def patch(ctx) : Hash(String, Alumna::AnyData)
    {} of String => Alumna::AnyData
  end

  def remove(ctx) : Bool
    true
  end
end

private def dispatch(svc, method)
  app = Alumna::App.new
  app.use("/boom", svc)
  ctx = Alumna::RuleContext.new(
    app: app, service: svc, path: "/boom", method: method,
    phase: Alumna::RulePhase::Before,
    params: Alumna::Http::ParamsView.new(HTTP::Params.new),
    headers: Alumna::Http::HeadersView.new(HTTP::Headers.new)
  )
  app.dispatch(svc, ctx)
  ctx
end

describe "Service::Base" do
  describe "error boundary in call_method" do
    it "wraps a raised Exception with message into 500" do
      svc = ExplodingService.new
      ctx = dispatch(svc, Alumna::ServiceMethod::Find)

      ctx.error.should_not be_nil
      err = ctx.error.as(Alumna::ServiceError)
      err.status.should eq(500)
      err.message.should eq("kaboom")
      ctx.phase.should eq(Alumna::RulePhase::Error)
      ctx.result_set?.should be_false
    end

    it "uses 'Unexpected error' when Exception.message is nil" do
      svc = ExplodingService.new
      ctx = dispatch(svc, Alumna::ServiceMethod::Get)

      ctx.error.should_not be_nil
      ctx.error.as(Alumna::ServiceError).message.should eq("Unexpected error")
    end
  end

  describe "block initialization" do
    it "yields self for rule registration" do
      schema = Alumna::Schema.new.str("x")

      svc = Alumna::MemoryAdapter.new(schema) do |s|
        s.before { |_c| nil }
        s.after { |_c| nil }
        s.error { |_c| nil }
      end

      # Check raw rules, not compiled pipelines
      svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
      svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::After).size.should eq(1)
      svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Error).size.should eq(1)
    end

    it "works with Alumna.memory factory" do
      schema = Alumna::Schema.new.str("y")

      svc = Alumna.memory(schema) do |s|
        s.before on: :create do |c|
          c.data["x"]? ? nil : Alumna::ServiceError.bad_request("missing x")
        end
      end

      svc.should be_a(Alumna::MemoryAdapter)
      svc.schema.should eq(schema)
      # Check raw rules
      svc.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::Before).size.should eq(1)
      svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(0)
    end

    it "preserves existing no-block initialization" do
      svc = Alumna::MemoryAdapter.new
      svc.schema.should be_nil
      svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).should be_empty
    end
  end
end
