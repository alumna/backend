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

  describe "Rules::RateLimiter" do
    app = App.new
    service = TestService.new

    it "allows requests under limit" do
      rule = Alumna.rate_limit(limit: 2, window_seconds: 60)
      ctx = RuleContext.new(
        app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "GET", remote_ip: "2.2.2.2"
      )

      r1 = rule.call(ctx)
      r2 = rule.call(ctx)

      r1.continue?.should be_true
      r2.continue?.should be_true
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
    end

    it "blocks over limit with 429" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60)
      ctx = RuleContext.new(
        app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "GET", remote_ip: "3.3.3.3"
      )

      rule.call(ctx)          # first
      result = rule.call(ctx) # second

      result.stop?.should be_true
      result.error.should_not be_nil
      result.error.try(&.status).should eq(429)
    end

    it "skips OPTIONS" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60)
      ctx = RuleContext.new(
        app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "OPTIONS", remote_ip: "4.4.4.4"
      )
      result = rule.call(ctx)
      result.continue?.should be_true
    end
  end
end
