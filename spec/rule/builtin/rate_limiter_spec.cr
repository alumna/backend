require "../../spec_helper"

module Alumna
  # :nocov:
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

  # :nocov:

  describe "Rules::RateLimiter" do
    app = App.new
    service = TestService.new

    it "allows requests under limit" do
      rule = Alumna.rate_limit(limit: 2, window_seconds: 60)
      ctx = RuleContext.new(app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "GET", remote_ip: "2.2.2.2")

      rule.call(ctx)
      ctx.http.headers["X-RateLimit-Remaining"].should eq("1")

      rule.call(ctx)
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
      ctx.http.headers["X-RateLimit-Limit"].should eq("2")
      ctx.http.headers["X-RateLimit-Reset"].should_not be_nil
    end

    it "blocks over limit with 429" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60)
      ctx = RuleContext.new(app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "GET", remote_ip: "3.3.3.3")

      rule.call(ctx)
      result = rule.call(ctx)

      result.stop?.should be_true
      result.error.try(&.status).should eq(429)
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
    end

    it "resets count after window expires" do
      # window 0 forces immediate expiry — hits lines 21-22
      rule = Alumna.rate_limit(limit: 1, window_seconds: 0)
      ctx = RuleContext.new(app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "GET", remote_ip: "5.5.5.5")

      first = rule.call(ctx)
      first.continue?.should be_true
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")

      # ensure now > r
      sleep 1.milliseconds

      second = rule.call(ctx)
      second.continue?.should be_true # counter reset, not blocked
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
    end

    it "skips OPTIONS" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60)
      ctx = RuleContext.new(app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "OPTIONS", remote_ip: "4.4.4.4")
      result = rule.call(ctx)
      result.continue?.should be_true
      ctx.http.headers.has_key?("X-RateLimit-Limit").should be_false
    end
  end
end
