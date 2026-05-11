require "../spec_helper"
require "../../src/testing"

def my_rule(ctx : Alumna::RuleContext) : Alumna::ServiceError?
  # The conditional forces the compiler to infer the exact union type: (ServiceError | Nil)
  ctx.id == "force-error" ? Alumna::ServiceError.internal : nil
end

describe "Alumna::Rule alias" do
  it "accepts a Proc that returns nil to continue" do
    rule = ->(ctx : Alumna::RuleContext) : Alumna::ServiceError? do
      ctx.headers["x"] = "1"
      nil
    end

    result = Alumna::Testing.run_rule(rule)

    result.error.should be_nil
    result.ctx.headers["x"].should eq("1")
  end

  it "accepts a Proc that returns ServiceError to stop" do
    rule = Alumna::Rule.new { |ctx| Alumna::ServiceError.forbidden }

    result = Alumna::Testing.run_rule(rule)

    result.error.should_not be_nil
    result.error.as(Alumna::ServiceError).status.should eq(403)
  end

  it "works with a captured method" do
    rule = ->my_rule(Alumna::RuleContext)

    result = Alumna::Testing.run_rule(rule)

    result.error.should be_nil
  end
end
