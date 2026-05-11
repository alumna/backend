require "../spec_helper"
require "../../src/testing"

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
  ctx = Alumna::Testing.build_ctx(
    app: app,
    service: svc,
    path: "/boom",
    method: method
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

      svc = Alumna.memory(schema) do # use the factory, not.new directly
        before { |_c| nil }
        after { |_c| nil }
        error { |_c| nil }
      end

      svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Before).size.should eq(1)
      svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::After).size.should eq(1)
      svc.collect_rules(Alumna::ServiceMethod::Find, Alumna::RulePhase::Error).size.should eq(1)
    end

    it "works with Alumna.memory factory" do
      schema = Alumna::Schema.new.str("y")

      svc = Alumna.memory(schema) do
        before on: :create do |c|
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

  describe "validate helper" do
    it "builds a rule from the service schema" do
      schema = Alumna::Schema.new.str("name", min_length: 1)

      svc = Alumna.memory(schema) do
        before validate, on: :create
      end

      rules = svc.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::Before)
      rules.size.should eq(1)

      # Simulate a failing validation
      ctx = Alumna::Testing.build_ctx(
        service: svc,
        method: Alumna::ServiceMethod::Create
      )

      err = rules.first.call(ctx)
      err.should_not be_nil
      err.as(Alumna::ServiceError).status.should eq(422)
    end

    it "accepts an explicit schema override" do
      schema1 = Alumna::Schema.new.str("a")
      schema2 = Alumna::Schema.new.str("b", min_length: 1)

      svc = Alumna.memory(schema1) do
        before validate(schema2), on: :create
      end

      rules = svc.collect_rules(Alumna::ServiceMethod::Create, Alumna::RulePhase::Before)
      ctx = Alumna::Testing.build_ctx(
        service: svc,
        method: Alumna::ServiceMethod::Create,
        data: {"b" => ""} of String => Alumna::AnyData
      )

      err = rules.first.call(ctx)
      err.as(Alumna::ServiceError).status.should eq(422)
    end

    it "raises at boot if service has no schema" do
      svc = Alumna::MemoryAdapter.new
      expect_raises(ArgumentError, "validate requires a schema") do
        svc.validate
      end
    end
  end
end
