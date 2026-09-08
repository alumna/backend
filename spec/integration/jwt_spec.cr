require "../spec_helper"
require "../../src/testing"

private SECRET = "s3cret-key-for-tests"

describe "JWT E2E" do
  it "issues a token and accepts it on a protected path" do
    app = Alumna::App.new
    app.use "/login", Alumna.memory(Alumna::Schema.new) {
      after on: :create do |ctx|
        ctx.result = Alumna.hash(token: Alumna::JWT.encode(Alumna.hash(sub: "u1", exp: Time.utc.to_unix + 60), SECRET))
        nil
      end
    }
    app.use "/me", Alumna.memory(Alumna::Schema.new) {
      before Alumna.jwt(SECRET)
      before do |ctx|
        claims = ctx.store["jwt"]?.as?(Hash(String, Alumna::AnyData))
        next Alumna::ServiceError.unauthorized unless claims
        ctx.result = claims
        nil
      end
    }

    client = Alumna::Testing::AppClient.new(app)
    login = client.post("/login")
    login.status.should eq(201)
    token = login.json_hash["token"].as(String)

    denied = client.get("/me")
    denied.status.should eq(401)
    denied.json_hash["error"].should eq("Missing token")

    me = client.get("/me", headers: {"Authorization" => "Bearer #{token}"})
    me.status.should eq(200)
    me.json_hash["sub"].should eq("u1")

    bad = client.get("/me", headers: {"Authorization" => "Bearer #{token[0..-2]}"})
    bad.status.should eq(401)
  end

  it "skips JWT on an internal call and uses the parent store" do
    app = Alumna::App.new
    app.before Alumna.jwt(SECRET)
    app.use "/inner", Alumna.memory(Alumna::Schema.new) {
      before do |ctx|
        claims = ctx.store["jwt"]?.as?(Hash(String, Alumna::AnyData))
        next Alumna::ServiceError.unauthorized unless claims
        ctx.result = claims
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

    token = Alumna::JWT.encode(Alumna.hash(sub: "u2"), SECRET)
    client = Alumna::Testing::AppClient.new(app)
    res = client.get("/outer", headers: {"Authorization" => "Bearer #{token}"})
    res.status.should eq(200)
    res.json_hash["sub"].should eq("u2")
  end
end
