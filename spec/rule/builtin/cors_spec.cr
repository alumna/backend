require "../../spec_helper"

module Alumna
  class TestService < Service
    def initialize
      super("/test")
    end

    def find(ctx : RuleContext) : Array(Hash(String, AnyData))
      [] of Hash(String, AnyData)
    end

    def get(ctx : RuleContext) : Hash(String, AnyData)?
      nil
    end

    def create(ctx : RuleContext) : Hash(String, AnyData)
      {} of String => AnyData
    end

    def update(ctx : RuleContext) : Hash(String, AnyData)
      {} of String => AnyData
    end

    def patch(ctx : RuleContext) : Hash(String, AnyData)
      {} of String => AnyData
    end

    def remove(ctx : RuleContext) : Bool
      false
    end
  end

  describe "Rules::Cors" do
    app = App.new
    service = TestService.new

    it "sets allow-origin for whitelisted origin" do
      ctx = RuleContext.new(
        app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "GET", remote_ip: "1.1.1.1",
        headers: {"origin" => "https://example.com"}
      )
      rule = Alumna.cors(origins: ["https://example.com"])
      rule.call(ctx)

      ctx.http.headers["Access-Control-Allow-Origin"].should eq("https://example.com")
      ctx.http.headers["Vary"].should eq("Origin")
    end

    it "allows wildcard" do
      ctx = RuleContext.new(
        app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "GET", remote_ip: "1.1.1.1",
        headers: {"origin" => "https://any.com"}
      )
      Alumna.cors(origins: ["*"]).call(ctx)
      ctx.http.headers["Access-Control-Allow-Origin"].should eq("*")
    end

    it "short-circuits OPTIONS preflight" do
      ctx = RuleContext.new(
        app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "OPTIONS", remote_ip: "1.1.1.1",
        headers: {"origin" => "https://example.com"}
      )
      Alumna.cors.call(ctx)

      ctx.http.status.should eq(204)
      ctx.result_set?.should be_true
    end
  end
end
