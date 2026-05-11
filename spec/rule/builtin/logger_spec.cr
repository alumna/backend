require "../../spec_helper"
require "../../../src/testing"

describe "Alumna.logger" do
  it "logs method, path, status and timing" do
    io = IO::Memory.new
    rule = Alumna.logger(io)

    # 1. Build context and simulate the Before phase
    ctx_before = Alumna::Testing.build_ctx(
      path: "/test",
      id: "123",
      http_method: "GET",
      remote_ip: "5.5.5.5",
      phase: Alumna::RulePhase::Before
    )

    Alumna::Testing.run_rule(rule, ctx: ctx_before)
    sleep 5.milliseconds

    # 2. Simulate the After phase with a new context
    ctx_after = Alumna::Testing.build_ctx(
      path: "/test",
      id: "123",
      http_method: "GET",
      remote_ip: "5.5.5.5",
      phase: Alumna::RulePhase::After
    )

    # Explicitly pass the state that the before-rule saved
    ctx_after.store["t0"] = ctx_before.store["t0"]
    ctx_after.http.status = 200

    Alumna::Testing.run_rule(rule, ctx: ctx_after)

    # 3. Assert on the output
    log = io.to_s.strip
    log.should match(/5\.5\.5\.5 "GET \/test\/123" 200 \d+\.\d+ms/)
    ms = log.split(' ').last.rchop("ms").to_f
    ms.should be > 0.0
    ms.should be < 100.0
  end

  it "logs errors" do
    io = IO::Memory.new
    rule = Alumna.logger(io)

    # 1. Build context and simulate the Before phase
    ctx_before = Alumna::Testing.build_ctx(
      path: "/test",
      http_method: "POST",
      remote_ip: "6.6.6.6",
      phase: Alumna::RulePhase::Before
    )

    Alumna::Testing.run_rule(rule, ctx: ctx_before)
    sleep 2.milliseconds

    # 2. Simulate the Error phase
    ctx_error = Alumna::Testing.build_ctx(
      path: "/test",
      http_method: "POST",
      remote_ip: "6.6.6.6",
      phase: Alumna::RulePhase::Error
    )

    # Pass the timing state and set the error
    ctx_error.store["t0"] = ctx_before.store["t0"]
    ctx_error.error = Alumna::ServiceError.not_found

    Alumna::Testing.run_rule(rule, ctx: ctx_error)

    # 3. Assert on the output
    log = io.to_s.strip
    log.should contain("6.6.6.6")
    log.should contain(%("POST /test"))
    log.should contain("404")
    log.should match(/\d+\.\d+ms$/)
    ms = log.split(' ').last.rchop("ms").to_f
    ms.should be > 0.0
  end
end
