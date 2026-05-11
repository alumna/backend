require "../../spec_helper"
require "../../../src/testing"

describe "Alumna.cors" do
  it "sets allow-origin and vary for whitelisted origin" do
    rule = Alumna.cors(origins: ["https://example.com"])
    res = Alumna::Testing.run_rule(rule, headers: {"Origin" => "https://example.com"})

    res.ctx.http.headers["Access-Control-Allow-Origin"].should eq("https://example.com")
    res.ctx.http.headers["Vary"].should eq("Origin")
    res.ctx.http.headers.has_key?("Access-Control-Allow-Credentials").should be_false
  end

  it "allows wildcard without credentials and omits vary" do
    rule = Alumna.cors(origins: ["*"])
    res = Alumna::Testing.run_rule(rule, headers: {"Origin" => "https://any.com"})

    res.ctx.http.headers["Access-Control-Allow-Origin"].should eq("*")
    res.ctx.http.headers.has_key?("Vary").should be_false
  end

  it "raises for wildcard with credentials" do
    expect_raises(ArgumentError, /wildcard.*credentials/) do
      Alumna.cors(origins: ["*"], credentials: true)
    end
  end

  it "sets credentials header for explicit origin" do
    rule = Alumna.cors(origins: ["https://app.example.com"], credentials: true)
    res = Alumna::Testing.run_rule(rule, headers: {"Origin" => "https://app.example.com"})

    res.ctx.http.headers["Access-Control-Allow-Origin"].should eq("https://app.example.com")
    res.ctx.http.headers["Access-Control-Allow-Credentials"].should eq("true")
    res.ctx.http.headers["Vary"].should eq("Origin")
  end

  it "does nothing when origin is missing" do
    res = Alumna::Testing.run_rule(Alumna.cors)
    res.ctx.http.headers.empty?.should be_true
  end

  it "does nothing for disallowed origin" do
    rule = Alumna.cors(origins: ["https://example.com"])
    res = Alumna::Testing.run_rule(rule, headers: {"Origin" => "https://evil.com"})

    res.ctx.http.headers.has_key?("Access-Control-Allow-Origin").should be_false
  end

  it "short-circuits real preflight" do
    rule = Alumna.cors(origins: ["https://example.com"])
    res = Alumna::Testing.run_rule(rule,
      http_method: "OPTIONS",
      headers: {
        "Origin"                        => "https://example.com",
        "Access-Control-Request-Method" => "POST",
      }
    )

    res.ctx.http.status.should eq(204)
    res.ctx.result_set?.should be_true
    res.ctx.http.headers["Access-Control-Allow-Methods"].should eq("GET, POST, PUT, PATCH, DELETE, OPTIONS")
    res.ctx.http.headers["Access-Control-Allow-Headers"].should eq("Content-Type, Authorization, Accept")
    res.ctx.http.headers["Access-Control-Max-Age"].should eq("86400")
  end

  it "does not short-circuit OPTIONS without preflight header" do
    rule = Alumna.cors
    res = Alumna::Testing.run_rule(rule,
      http_method: "OPTIONS",
      headers: {"Origin" => "https://example.com"}
    )

    res.ctx.http.status.should be_nil
    res.ctx.result_set?.should be_false
    res.ctx.http.headers["Access-Control-Allow-Origin"].should eq("*")
  end

  it "does not short-circuit preflight for disallowed origin" do
    rule = Alumna.cors(origins: ["https://example.com"])
    res = Alumna::Testing.run_rule(rule,
      http_method: "OPTIONS",
      headers: {
        "Origin"                        => "https://evil.com",
        "Access-Control-Request-Method" => "POST",
      }
    )

    res.ctx.http.status.should be_nil
    res.ctx.result_set?.should be_false
    res.ctx.http.headers.has_key?("Access-Control-Allow-Origin").should be_false
  end

  it "normalizes origins case-insensitively and ignores trailing slash" do
    # config has upper case, spaces, and a trailing slash
    rule = Alumna.cors(origins: ["  HTTPS://example.com/ "])
    res = Alumna::Testing.run_rule(rule, headers: {"Origin" => "https://EXAMPLE.COM"})

    res.ctx.http.headers["Access-Control-Allow-Origin"].should eq("https://EXAMPLE.COM")
    res.ctx.http.headers["Vary"].should eq("Origin")
  end

  it "rejects mismatched origin even after normalization" do
    rule = Alumna.cors(origins: ["https://example.com/"])
    res = Alumna::Testing.run_rule(rule, headers: {"Origin" => "https://evil.com"})

    res.ctx.http.headers.has_key?("Access-Control-Allow-Origin").should be_false
  end
end
