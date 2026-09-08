require "../../spec_helper"
require "../../../src/testing"

describe Alumna::Session do
  it "rejects an empty cookie name" do
    expect_raises(ArgumentError, "session cookie name must not be empty") do
      Alumna::Session.new(Alumna::MemorySessionStore.new, cookie: "")
    end
  end

  it "rejects same_site :none without secure" do
    expect_raises(ArgumentError, "session same_site: :none requires secure: true") do
      Alumna::Session.new(Alumna::MemorySessionStore.new, same_site: :none)
    end
  end

  it "rejects an unknown same_site symbol" do
    expect_raises(ArgumentError, "same_site must be :lax, :strict, or :none") do
      Alumna::Session.new(Alumna::MemorySessionStore.new, same_site: :bogus)
    end
  end

  it "allows same_site :none with secure" do
    Alumna::Session.new(Alumna::MemorySessionStore.new, same_site: :none, secure: true)
  end
end

describe "Alumna.session" do
  it "returns 401 Missing session when the cookie is absent" do
    store = Alumna::MemorySessionStore.new
    rule = Alumna.session(store)
    res = Alumna::Testing.run_rule(rule)
    err = res.error
    err.should_not be_nil
    if err
      err.status.should eq(401)
      err.message.should eq("Missing session")
    end
  end

  it "continues when the cookie is absent and required is false" do
    store = Alumna::MemorySessionStore.new
    rule = Alumna.session(store, required: false)
    res = Alumna::Testing.run_rule(rule)
    res.error.should be_nil
    res.ctx.store.has_key?("session").should be_false
  end

  it "returns 401 for an unknown id" do
    store = Alumna::MemorySessionStore.new
    rule = Alumna.session(store)
    res = Alumna::Testing.run_rule(rule, headers: {"Cookie" => "alumna.sid=nope"})
    err = res.error
    err.should_not be_nil
    if err
      err.status.should eq(401)
      err.message.should eq("Unauthorized")
    end
  end

  it "returns 401 for an empty cookie value" do
    store = Alumna::MemorySessionStore.new
    rule = Alumna.session(store)
    res = Alumna::Testing.run_rule(rule, headers: {"Cookie" => "alumna.sid="})
    err = res.error
    if err
      err.status.should eq(401)
      err.message.should eq("Missing session")
    end
  end

  it "loads session data into ctx.store" do
    store = Alumna::MemorySessionStore.new
    sessions = Alumna::Session.new(store)
    ctx = Alumna::Testing.build_ctx
    id = sessions.start(ctx, Alumna.hash(user_id: "42"))

    rule = sessions.rule
    res = Alumna::Testing.run_rule(rule, headers: {"Cookie" => "alumna.sid=#{id}"})
    res.error.should be_nil
    stored = res.ctx.store["session"]?
    stored.should be_a(Hash(String, Alumna::AnyData))
    if stored.is_a?(Hash(String, Alumna::AnyData))
      stored["user_id"].should eq("42")
    end
  end

  it "skips OPTIONS" do
    store = Alumna::MemorySessionStore.new
    rule = Alumna.session(store)
    res = Alumna::Testing.run_rule(rule, http_method: "OPTIONS")
    res.error.should be_nil
  end

  it "skips internal and local providers" do
    store = Alumna::MemorySessionStore.new
    rule = Alumna.session(store)
    Alumna::Testing.run_rule(rule, provider: "internal").error.should be_nil
    Alumna::Testing.run_rule(rule, provider: "local").error.should be_nil
  end

  it "does not skip rest" do
    store = Alumna::MemorySessionStore.new
    rule = Alumna.session(store)
    err = Alumna::Testing.run_rule(rule, provider: "rest").error
    err.should_not be_nil
  end

  it "can disable skip_providers" do
    store = Alumna::MemorySessionStore.new
    rule = Alumna.session(store, skip_providers: [] of String)
    err = Alumna::Testing.run_rule(rule, provider: "internal").error
    err.should_not be_nil
    if err
      err.message.should eq("Missing session")
    end
  end
end

describe "Alumna::Session start/stop/rotate" do
  it "start writes Set-Cookie and the store" do
    store = Alumna::MemorySessionStore.new(ttl: 1.hour)
    sessions = Alumna::Session.new(store, http_only: true, same_site: :lax)
    ctx = Alumna::Testing.build_ctx
    id = sessions.start(ctx, Alumna.hash(user_id: "1"))

    store.get(id).try(&.["user_id"]).should eq("1")
    cookies = ctx.http.cookies?
    cookies.should_not be_nil
    if cookies
      cookies.size.should eq(1)
      header = cookies.first.to_set_cookie_header
      header.should contain("alumna.sid=#{id}")
      header.should contain("HttpOnly")
      header.should contain("SameSite=Lax")
      header.should contain("max-age=3600")
    end
    ctx.store["session"].should eq(Alumna.hash(user_id: "1"))
  end

  it "start accepts a per-call ttl" do
    store = Alumna::MemorySessionStore.new(ttl: 1.hour)
    sessions = Alumna::Session.new(store)
    ctx = Alumna::Testing.build_ctx
    id = sessions.start(ctx, Alumna.hash(n: "1"), ttl: 1.nanosecond)
    sleep 1.milliseconds
    store.get(id).should be_nil
  end

  it "stop deletes the session and expires the cookie" do
    store = Alumna::MemorySessionStore.new
    sessions = Alumna::Session.new(store)
    start_ctx = Alumna::Testing.build_ctx
    id = sessions.start(start_ctx, Alumna.hash(user_id: "1"))

    ctx = Alumna::Testing.build_ctx(headers: {"Cookie" => "alumna.sid=#{id}"})
    ctx.store["session"] = Alumna.hash(user_id: "1")
    sessions.stop(ctx)

    store.get(id).should be_nil
    ctx.store.has_key?("session").should be_false
    cookies = ctx.http.cookies?
    cookies.should_not be_nil
    if cookies
      cookies.first.to_set_cookie_header.should contain("max-age=0")
    end
  end

  it "rotate issues a new id and drops the old id" do
    store = Alumna::MemorySessionStore.new
    sessions = Alumna::Session.new(store)
    start_ctx = Alumna::Testing.build_ctx
    old_id = sessions.start(start_ctx, Alumna.hash(user_id: "1"))

    ctx = Alumna::Testing.build_ctx(headers: {"Cookie" => "alumna.sid=#{old_id}"})
    new_id = sessions.rotate(ctx, Alumna.hash(user_id: "1"))

    new_id.should_not eq(old_id)
    store.get(old_id).should be_nil
    store.get(new_id).try(&.["user_id"]).should eq("1")
  end

  it "stop without a cookie still expires the client cookie" do
    sessions = Alumna::Session.new(Alumna::MemorySessionStore.new)
    ctx = Alumna::Testing.build_ctx
    sessions.stop(ctx)
    header = ctx.http.cookies.first.to_set_cookie_header
    header.should contain("max-age=0")
  end

  it "class helpers use the default cookie name" do
    store = Alumna::MemorySessionStore.new
    ctx = Alumna::Testing.build_ctx
    id = Alumna::Session.start(ctx, store, Alumna.hash(user_id: "9"))
    store.get(id).try(&.["user_id"]).should eq("9")

    ctx2 = Alumna::Testing.build_ctx(headers: {"Cookie" => "alumna.sid=#{id}"})
    Alumna::Session.stop(ctx2, store)
    store.get(id).should be_nil

    ctx3 = Alumna::Testing.build_ctx
    id2 = Alumna::Session.start(ctx3, store, Alumna.hash(user_id: "8"))
    ctx4 = Alumna::Testing.build_ctx(headers: {"Cookie" => "alumna.sid=#{id2}"})
    id3 = Alumna::Session.rotate(ctx4, store, Alumna.hash(user_id: "8"))
    id3.should_not eq(id2)
    store.get(id2).should be_nil
    store.get(id3).try(&.["user_id"]).should eq("8")
  end

  it "sets Secure and custom cookie name" do
    store = Alumna::MemorySessionStore.new
    sessions = Alumna::Session.new(store, cookie: "sid", secure: true, same_site: :strict, path: "/app")
    ctx = Alumna::Testing.build_ctx
    id = sessions.start(ctx, Alumna.hash(x: "1"))
    header = ctx.http.cookies.first.to_set_cookie_header
    header.should contain("sid=#{id}")
    header.should contain("Secure")
    header.should contain("SameSite=Strict")
    header.should contain("path=/app")
  end
end
