require "../spec_helper"
require "../../src/testing"

describe "Session E2E" do
  it "logs in, reads a protected path, then logs out" do
    store = Alumna::MemorySessionStore.new(ttl: 1.hour)
    sessions = Alumna::Session.new(store)

    app = Alumna::App.new
    app.use "/login", Alumna.memory(Alumna::Schema.new) {
      after on: :create do |ctx|
        sessions.start(ctx, Alumna.hash(user_id: "u1"))
        nil
      end
    }
    app.use "/me", Alumna.memory(Alumna::Schema.new) {
      before sessions.rule
      before do |ctx|
        session = ctx.store["session"]?.as?(Hash(String, Alumna::AnyData))
        next Alumna::ServiceError.unauthorized unless session
        ctx.result = session
        nil
      end
    }
    app.use "/logout", Alumna.memory(Alumna::Schema.new) {
      before sessions.rule
      after on: :create do |ctx|
        sessions.stop(ctx)
        nil
      end
    }

    client = Alumna::Testing::AppClient.new(app)

    login = client.post("/login")
    login.status.should eq(201)
    set_cookie = login.headers["Set-Cookie"]?
    set_cookie.should_not be_nil
    sid = set_cookie ? Alumna::Http.cookie_value(set_cookie.split(';').first, "alumna.sid") : nil
    sid.should_not be_nil

    denied = client.get("/me")
    denied.status.should eq(401)
    denied.json_hash["error"].should eq("Missing session")

    cookie_header = "alumna.sid=#{sid}"
    me = client.get("/me", headers: {"Cookie" => cookie_header})
    me.status.should eq(200)
    me.json_hash["user_id"].should eq("u1")

    logout = client.post("/logout", headers: {"Cookie" => cookie_header})
    logout.status.should eq(201)
    logout.headers["Set-Cookie"]?.to_s.should contain("max-age=0")

    after = client.get("/me", headers: {"Cookie" => cookie_header})
    after.status.should eq(401)
    after.json_hash["error"].should eq("Unauthorized")
  end

  it "does not require a cookie on an internal call after HTTP auth" do
    store = Alumna::MemorySessionStore.new
    sessions = Alumna::Session.new(store)

    app = Alumna::App.new
    app.before sessions.rule
    app.use "/inner", Alumna.memory(Alumna::Schema.new) {
      before do |ctx|
        session = ctx.store["session"]?.as?(Hash(String, Alumna::AnyData))
        next Alumna::ServiceError.unauthorized unless session
        ctx.result = session
        nil
      end
    }
    app.use "/outer", Alumna.memory(Alumna::Schema.new) {
      before do |ctx|
        res, err = ctx.call("/inner", :find)
        next err if err
        ctx.result = res
        nil
      end
    }

    start_ctx = Alumna::Testing.build_ctx
    id = sessions.start(start_ctx, Alumna.hash(user_id: "u2"))
    client = Alumna::Testing::AppClient.new(app)
    res = client.get("/outer", headers: {"Cookie" => "alumna.sid=#{id}"})
    res.status.should eq(200)
    res.json_hash["user_id"].should eq("u2")
  end
end
