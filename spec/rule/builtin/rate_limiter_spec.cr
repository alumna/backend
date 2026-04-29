require "../../spec_helper"

private def build_ctx_rate_limiter(app : Alumna::App, service : Alumna::Service, ip : String, method = "GET") : Alumna::RuleContext
  svc_method = method == "OPTIONS" ? Alumna::ServiceMethod::Options : Alumna::ServiceMethod::Find

  Alumna::RuleContext.new(
    app: app, service: service, path: "/test",
    method: svc_method, phase: Alumna::RulePhase::Before,
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
    app = uninitialized App
    service = uninitialized TestService

    before_each do
      app = App.new
      service = TestService.new
    end

    it "allows requests under limit" do
      rule = Alumna.rate_limit(limit: 2, window_seconds: 60)
      ctx = build_ctx_rate_limiter(app, service, "2.2.2")
      rule.call(ctx)
      ctx.http.headers["X-RateLimit-Remaining"].should eq("1")
      rule.call(ctx)
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
      ctx.http.headers["X-RateLimit-Limit"].should eq("2")
      ctx.http.headers["X-RateLimit-Reset"].should_not be_nil
    end

    it "blocks over limit with 429" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60)
      ctx = build_ctx_rate_limiter(app, service, "3.3.3")
      rule.call(ctx)
      result = rule.call(ctx)
      result.stop?.should be_true
      result.error.try(&.status).should eq(429)
      ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
    end

    it "resets count after window expires" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 0)
      ctx = build_ctx_rate_limiter(app, service, "5.5.5.5")
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
      ctx = build_ctx_rate_limiter(app, service, "4.4.4.4", "OPTIONS")
      result = rule.call(ctx)
      result.continue?.should be_true
      ctx.http.headers.has_key?("X-RateLimit-Limit").should be_false
    end

    # --- new tests for the bounded store ---

    it "isolates counts per key" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60, key: ->(ctx : RuleContext) { ctx.remote_ip })
      ctx_a = build_ctx_rate_limiter(app, service, "10.0.0.1")
      ctx_b = build_ctx_rate_limiter(app, service, "10.0.0.2")

      rule.call(ctx_a).continue?.should be_true
      rule.call(ctx_b).continue?.should be_true
      # second hit for A should block, B still has its own bucket
      rule.call(ctx_a).stop?.should be_true
      rule.call(ctx_b).stop?.should be_true
    end

    it "prunes expired entries to prevent unbounded growth" do
      store = RateLimitStore.new(10.milliseconds, cleanup_every: 1000)
      store.hit("a")
      store.hit("b")
      store.size.should eq(2)

      sleep 15.milliseconds
      # entries are expired but still present until pruned
      store.size.should eq(2)

      store.prune_expired
      store.size.should eq(0)

      # new hit creates fresh window
      count, _ = store.hit("a")
      count.should eq(1)
      store.size.should eq(1)
    end

    it "cleans up automatically every N operations" do
      # use tiny cleanup_every to avoid sleeping in CI
      store = RateLimitStore.new(5.milliseconds, cleanup_every: 2)
      store.hit("x") # ops=1
      store.hit("y") # ops=2 -> triggers cleanup, but nothing expired yet
      store.size.should eq(2)

      sleep 6.milliseconds
      store.hit("z") # ops=1, x and y are expired but not yet cleaned
      store.size.should eq(3)

      store.hit("w")          # ops=2 -> triggers cleanup, removes x and y
      store.size.should eq(2) # only z and w remain
    end
  end
end
