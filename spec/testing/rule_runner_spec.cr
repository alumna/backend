require "../spec_helper"
require "../../src/testing"

describe Alumna::Testing do
  describe ".run_rule" do
    it "runs a rule that continues (returns nil)" do
      rule = Alumna::Rule.new do |ctx|
        ctx.headers["X-Mutated"] = "true"
        nil
      end

      result = Alumna::Testing.run_rule(rule)

      result.error.should be_nil
      result.ctx.headers["X-Mutated"].should eq("true")
    end

    it "runs a rule that stops (returns ServiceError)" do
      rule = Alumna::Rule.new do |ctx|
        Alumna::ServiceError.unauthorized("Stop right there")
      end

      result = Alumna::Testing.run_rule(rule)

      result.error.should_not be_nil
      if err = result.error
        err.status.should eq(401)
        err.message.should eq("Stop right there")
      end
      # Ensure context also has the error set, simulating the Orchestrator
      result.ctx.error.should eq(result.error)
    end

    it "accepts an explicit context" do
      ctx = Alumna::Testing.build_ctx(remote_ip: "9.9.9.9")
      rule = Alumna::Rule.new do |c|
        c.remote_ip == "9.9.9.9" ? nil : Alumna::ServiceError.forbidden
      end

      result = Alumna::Testing.run_rule(rule, ctx: ctx)
      result.error.should be_nil
    end

    it "accepts keyword arguments to build the context implicitly" do
      rule = Alumna::Rule.new do |c|
        c.headers["auth"]? == "secret" ? nil : Alumna::ServiceError.unauthorized
      end

      # Implicit context built with specific headers
      result = Alumna::Testing.run_rule(rule, headers: {"auth" => "secret"})
      result.error.should be_nil

      # Failure case
      result2 = Alumna::Testing.run_rule(rule, headers: {"auth" => "wrong"})
      result2.error.should_not be_nil
    end
  end
end
