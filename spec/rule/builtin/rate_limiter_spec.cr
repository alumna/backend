require "../../spec_helper"

private def build_ctx(app : Alumna::App, service : Alumna::Service, ip : String, method = "GET") : Alumna::RuleContext
  Alumna::RuleContext.new(
    app: app, service: service, path: "/test",
    method: Alumna::ServiceMethod::Find, phase: Alumna::RulePhase::Before,
    params: Alumna::Http::ParamsView.new(HTTP::Params.new),
    headers: Alumna::Http::HeadersView.new(HTTP::Headers.new),
    http_method: method, remote_ip: ip
  )
end

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

  describe "Rules::RateLimiter" do
    app = App.new
    service = TestService.new

    it "allows requests under limit" do
      rule = Alumna.rate_limit(limit: 2, window_seconds: 60)
      ctx = build_ctx(app, service, "2.2.2")
      rule.call(ctx)
      ctx.http.headers["X-RateLimit-Remaining"].should eq("1")
      rule.call(ctx)
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
      ctx.http.headers["X-RateLimit-Limit"].should eq("2")
      ctx.http.headers["X-RateLimit-Reset"].should_not be_nil
    end

    it "blocks over limit with 429" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60)
      ctx = build_ctx(app, service, "3.3.3")
      rule.call(ctx)
      result = rule.call(ctx)
      result.stop?.should be_true
      result.error.try(&.status).should eq(429)
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
    end

    it "resets count after window expires" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 0)
      ctx = build_ctx(app, service, "5.5.5.5")
      first = rule.call(ctx)
      first.continue?.should be_true
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
      sleep 1.milliseconds
      second = rule.call(ctx)
      second.continue?.should be_true
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
    end

    it "skips OPTIONS" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60)
      ctx = build_ctx(app, service, "4.4.4.4", "OPTIONS")
      result = rule.call(ctx)
      result.continue?.should be_true
      ctx.http.headers.has_key?("X-RateLimit-Limit").should be_false
    end
  end
end
