require "../../spec_helper"

module Alumna
  class TestService < Service
    def initialize
      super()
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

  def self.build_ctx_cors(app, service, origin : String? = nil, http_method = "GET", acrm : String? = nil)
    headers = HTTP::Headers.new
    headers["Origin"] = origin if origin
    headers["Access-Control-Request-Method"] = acrm if acrm
    method = http_method == "OPTIONS" ? ServiceMethod::Options : ServiceMethod::Find
    RuleContext.new(
      app: app,
      service: service,
      path: "/test",
      method: method,
      phase: RulePhase::Before,
      params: Http::ParamsView.new(HTTP::Params.new),
      headers: Http::HeadersView.new(headers),
      http_method: http_method,
      remote_ip: "1.1.1.1"
    )
  end

  describe "Rules::Cors" do
    app = uninitialized App
    service = uninitialized TestService

    before_each do
      app = App.new
      service = TestService.new
    end

    it "sets allow-origin and vary for whitelisted origin" do
      ctx = build_ctx_cors(app, service, "https://example.com")
      Alumna.cors(origins: ["https://example.com"]).call(ctx)

      ctx.http.headers["Access-Control-Allow-Origin"].should eq("https://example.com")
      ctx.http.headers["Vary"].should eq("Origin")
      ctx.http.headers.has_key?("Access-Control-Allow-Credentials").should be_false
    end

    it "allows wildcard without credentials and omits vary" do
      ctx = build_ctx_cors(app, service, "https://any.com")
      Alumna.cors(origins: ["*"]).call(ctx)

      ctx.http.headers["Access-Control-Allow-Origin"].should eq("*")
      ctx.http.headers.has_key?("Vary").should be_false
    end

    it "raises for wildcard with credentials" do
      expect_raises(ArgumentError, /wildcard.*credentials/) do
        Alumna.cors(origins: ["*"], credentials: true)
      end
    end

    it "sets credentials header for explicit origin" do
      ctx = build_ctx_cors(app, service, "https://app.example.com")
      Alumna.cors(origins: ["https://app.example.com"], credentials: true).call(ctx)

      ctx.http.headers["Access-Control-Allow-Origin"].should eq("https://app.example.com")
      ctx.http.headers["Access-Control-Allow-Credentials"].should eq("true")
      ctx.http.headers["Vary"].should eq("Origin")
    end

    it "does nothing when origin is missing" do
      ctx = build_ctx_cors(app, service, nil)
      Alumna.cors.call(ctx)
      ctx.http.headers.empty?.should be_true
    end

    it "does nothing for disallowed origin" do
      ctx = build_ctx_cors(app, service, "https://evil.com")
      Alumna.cors(origins: ["https://example.com"]).call(ctx)
      ctx.http.headers.has_key?("Access-Control-Allow-Origin").should be_false
    end

    it "short-circuits real preflight" do
      ctx = build_ctx_cors(app, service, "https://example.com", "OPTIONS", "POST")
      Alumna.cors(origins: ["https://example.com"]).call(ctx)

      ctx.http.status.should eq(204)
      ctx.result_set?.should be_true
      ctx.http.headers["Access-Control-Allow-Methods"].should eq("GET, POST, PUT, PATCH, DELETE, OPTIONS")
      ctx.http.headers["Access-Control-Allow-Headers"].should eq("Content-Type, Authorization, Accept")
      ctx.http.headers["Access-Control-Max-Age"].should eq("86400")
    end

    it "does not short-circuit OPTIONS without preflight header" do
      ctx = build_ctx_cors(app, service, "https://example.com", "OPTIONS", nil)
      Alumna.cors.call(ctx)

      ctx.http.status.should be_nil
      ctx.result_set?.should be_false
      ctx.http.headers["Access-Control-Allow-Origin"].should eq("*")
    end

    it "does not short-circuit preflight for disallowed origin" do
      ctx = build_ctx_cors(app, service, "https://evil.com", "OPTIONS", "POST")
      Alumna.cors(origins: ["https://example.com"]).call(ctx)

      ctx.http.status.should be_nil
      ctx.result_set?.should be_false
      ctx.http.headers.has_key?("Access-Control-Allow-Origin").should be_false
    end

    it "normalizes origins case-insensitively and ignores trailing slash" do
      ctx = build_ctx_cors(app, service, "https://EXAMPLE.COM")
      # config has upper case, spaces, and a trailing slash
      Alumna.cors(origins: ["  HTTPS://example.com/ "]).call(ctx)

      ctx.http.headers["Access-Control-Allow-Origin"].should eq("https://EXAMPLE.COM")
      ctx.http.headers["Vary"].should eq("Origin")
    end

    it "rejects mismatched origin even after normalization" do
      ctx = build_ctx_cors(app, service, "https://evil.com")
      Alumna.cors(origins: ["https://example.com/"]).call(ctx)

      ctx.http.headers.has_key?("Access-Control-Allow-Origin").should be_false
    end
  end
end
