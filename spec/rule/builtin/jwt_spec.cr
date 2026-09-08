require "../../spec_helper"
require "../../../src/testing"

private SECRET = "s3cret-key-for-tests"

describe "Alumna.jwt" do
  it "rejects an empty secret at boot" do
    expect_raises(ArgumentError, "jwt secret must not be empty") do
      Alumna.jwt("")
    end
  end

  it "rejects an empty header name at boot" do
    expect_raises(ArgumentError, "jwt header name must not be empty") do
      Alumna.jwt(SECRET, header: "")
    end
  end

  it "returns 401 Missing token when the header is absent" do
    rule = Alumna.jwt(SECRET)
    err = Alumna::Testing.run_rule(rule).error
    err.should_not be_nil
    if err
      err.status.should eq(401)
      err.message.should eq("Missing token")
    end
  end

  it "continues when the header is absent and required is false" do
    rule = Alumna.jwt(SECRET, required: false)
    res = Alumna::Testing.run_rule(rule)
    res.error.should be_nil
    res.ctx.store.has_key?("jwt").should be_false
  end

  it "loads claims into ctx.store" do
    token = Alumna::JWT.encode(Alumna.hash(sub: "u1"), SECRET)
    rule = Alumna.jwt(SECRET)
    res = Alumna::Testing.run_rule(rule, headers: {"Authorization" => "Bearer #{token}"})
    res.error.should be_nil
    stored = res.ctx.store["jwt"]?
    stored.should be_a(Hash(String, Alumna::AnyData))
    if stored.is_a?(Hash(String, Alumna::AnyData))
      stored["sub"].should eq("u1")
    end
  end

  it "accepts a case-insensitive scheme" do
    token = Alumna::JWT.encode(Alumna.hash(sub: "u1"), SECRET)
    rule = Alumna.jwt(SECRET)
    res = Alumna::Testing.run_rule(rule, headers: {"Authorization" => "bearer #{token}"})
    res.error.should be_nil
  end

  it "accepts a raw token when scheme is empty" do
    token = Alumna::JWT.encode(Alumna.hash(sub: "u1"), SECRET)
    rule = Alumna.jwt(SECRET, scheme: "")
    res = Alumna::Testing.run_rule(rule, headers: {"Authorization" => token})
    res.error.should be_nil
  end

  it "returns 401 for an empty raw token when scheme is empty" do
    rule = Alumna.jwt(SECRET, scheme: "")
    err = Alumna::Testing.run_rule(rule, headers: {"Authorization" => ""}).error
    err.should_not be_nil
  end

  it "returns 401 for a wrong scheme" do
    token = Alumna::JWT.encode(Alumna.hash(sub: "u1"), SECRET)
    rule = Alumna.jwt(SECRET)
    err = Alumna::Testing.run_rule(rule, headers: {"Authorization" => "Basic #{token}"}).error
    err.should_not be_nil
    if err
      err.message.should eq("Unauthorized")
    end
  end

  it "returns 401 for a tampered token" do
    token = Alumna::JWT.encode(Alumna.hash(sub: "u1"), SECRET)
    rule = Alumna.jwt(SECRET)
    err = Alumna::Testing.run_rule(rule, headers: {"Authorization" => "Bearer #{token}x"}).error
    err.should_not be_nil
    if err
      err.status.should eq(401)
      err.message.should eq("Unauthorized")
    end
  end

  it "skips OPTIONS and internal/local providers" do
    rule = Alumna.jwt(SECRET)
    Alumna::Testing.run_rule(rule, http_method: "OPTIONS").error.should be_nil
    Alumna::Testing.run_rule(rule, provider: "internal").error.should be_nil
    Alumna::Testing.run_rule(rule, provider: "local").error.should be_nil
  end

  it "uses a custom store key" do
    token = Alumna::JWT.encode(Alumna.hash(sub: "u1"), SECRET)
    rule = Alumna.jwt(SECRET, store_key: "claims")
    res = Alumna::Testing.run_rule(rule, headers: {"Authorization" => "Bearer #{token}"})
    res.ctx.store.has_key?("claims").should be_true
    res.ctx.store.has_key?("jwt").should be_false
  end
end
