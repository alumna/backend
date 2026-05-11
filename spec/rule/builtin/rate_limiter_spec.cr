require "../../spec_helper"
require "../../../src/testing"

module Alumna
  describe "Alumna.rate_limit" do
    it "allows requests under limit" do
      rule = Alumna.rate_limit(limit: 2, window_seconds: 60)

      res1 = Alumna::Testing.run_rule(rule, remote_ip: "2.2.2.2")
      res1.ctx.http.headers["X-RateLimit-Remaining"].should eq("1")

      res2 = Alumna::Testing.run_rule(rule, remote_ip: "2.2.2.2")
      res2.ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
      res2.ctx.http.headers["X-RateLimit-Limit"].should eq("2")
      res2.ctx.http.headers["X-RateLimit-Reset"].should_not be_nil
    end

    it "blocks over limit with 429" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60)

      Alumna::Testing.run_rule(rule, remote_ip: "3.3.3.3")
      res2 = Alumna::Testing.run_rule(rule, remote_ip: "3.3.3.3")

      res2.error.should_not be_nil
      res2.error.try(&.status).should eq(429)
      res2.ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
    end

    it "resets count after window expires" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 0)

      res1 = Alumna::Testing.run_rule(rule, remote_ip: "5.5.5.5")
      res1.error.should be_nil
      res1.ctx.http.headers["X-RateLimit-Remaining"].should eq("0")

      sleep 1.milliseconds

      res2 = Alumna::Testing.run_rule(rule, remote_ip: "5.5.5.5")
      res2.error.should be_nil
      res2.ctx.http.headers["X-RateLimit-Remaining"].should eq("0")
    end

    it "skips OPTIONS" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60)

      res = Alumna::Testing.run_rule(rule, remote_ip: "4.4.4.4", http_method: "OPTIONS")

      res.error.should be_nil
      res.ctx.http.headers.has_key?("X-RateLimit-Limit").should be_false
    end

    # --- new tests for the bounded store ---

    it "isolates counts per key" do
      rule = Alumna.rate_limit(limit: 1, window_seconds: 60, key: ->(ctx : RuleContext) { ctx.remote_ip })

      Alumna::Testing.run_rule(rule, remote_ip: "10.0.0.1").error.should be_nil
      Alumna::Testing.run_rule(rule, remote_ip: "10.0.0.2").error.should be_nil

      # second hit for A should block, B still has its own bucket
      Alumna::Testing.run_rule(rule, remote_ip: "10.0.0.1").error.should_not be_nil
      Alumna::Testing.run_rule(rule, remote_ip: "10.0.0.2").error.should_not be_nil
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
