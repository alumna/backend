require "../spec_helper"
require "../../src/testing"

describe Alumna::Testing do
  describe ".build_ctx" do
    it "builds a context with sensible defaults" do
      ctx = Alumna::Testing.build_ctx
      ctx.path.should eq("/test")
      ctx.method.should eq(Alumna::ServiceMethod::Find)
      ctx.phase.should eq(Alumna::RulePhase::Before)
      ctx.http_method.should eq("GET")
      ctx.remote_ip.should eq("127.0.0.1")
      ctx.provider.should eq("rest")
      ctx.id.should be_nil
      ctx.data.empty?.should be_true

      has_params = false
      ctx.params.each { has_params = true }
      has_params.should be_false
    end

    it "allows overriding specific fields" do
      ctx = Alumna::Testing.build_ctx(
        path: "/users",
        method: Alumna::ServiceMethod::Create,
        phase: Alumna::RulePhase::After,
        http_method: "POST",
        remote_ip: "10.0.0.1",
        provider: "websocket",
        id: "42",
        data: {"name" => "Alice"} of String => Alumna::AnyData,
        params: {"sort" => "desc"},
        headers: {"Authorization" => "Bearer token"}
      )

      ctx.path.should eq("/users")
      ctx.method.should eq(Alumna::ServiceMethod::Create)
      ctx.phase.should eq(Alumna::RulePhase::After)
      ctx.http_method.should eq("POST")
      ctx.remote_ip.should eq("10.0.0.1")
      ctx.provider.should eq("websocket")
      ctx.id.should eq("42")
      ctx.data["name"].should eq("Alice")
      ctx.params["sort"].should eq("desc")
      ctx.headers["authorization"].should eq("Bearer token")
    end
  end
end
