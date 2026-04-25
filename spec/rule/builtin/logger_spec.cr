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

  describe "Rules::Logger" do
    app = App.new
    service = TestService.new

    it "logs method, path, status and timing" do
      io = IO::Memory.new
      rule = Alumna.logger(io)

      ctx = RuleContext.new(
        app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "GET", remote_ip: "5.5.5.5"
      )
      ctx.id = "123"

      rule.call(ctx) # before

      sleep 5.milliseconds # long enough to be >0.0ms on CI

      ctx.phase = RulePhase::After
      ctx.http.status = 200
      rule.call(ctx) # after

      log = io.to_s.strip

      # full format check
      log.should match(/5\.5\.5\.5 "GET \/test\/123" 200 \d+\.\d+ms/)

      # extract ms and assert it's actually measured
      ms = log.split(' ').last.rchop("ms").to_f
      ms.should be > 0.0
      ms.should be < 100.0 # sanity bound for test
    end

    it "logs errors" do
      io = IO::Memory.new
      rule = Alumna.logger(io)

      ctx = RuleContext.new(
        app: app, service: service, path: "/test",
        method: ServiceMethod::Find, phase: RulePhase::Before,
        http_method: "POST", remote_ip: "6.6.6.6"
      )
      rule.call(ctx)

      sleep 2.milliseconds

      ctx.phase = RulePhase::Error
      ctx.error = ServiceError.not_found
      rule.call(ctx)

      log = io.to_s.strip
      log.should contain("6.6.6.6")
      log.should contain(%("POST /test"))
      log.should contain("404")
      log.should match(/\d+\.\d+ms$/)

      ms = log.split(' ').last.rchop("ms").to_f
      ms.should be > 0.0
    end
  end
end
