require "../spec_helper"
require "json"
require "../../src/testing"

TestSchema = Alumna::Schema.new
  .str("title", required_on: [:create, :update], min_length: 1, max_length: 100)
  .str("content", required: false)

Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "Bearer test-token" ? nil : Alumna::ServiceError.unauthorized
end

AfterLogger = Alumna::Rule.new do |ctx|
  ctx.http.headers["X-Request-ID"] = Random::Secure.hex(8)
  nil
end

ErrorLogger = Alumna::Rule.new do |ctx|
  ctx.http.headers["X-Error-ID"] = "err-123"
  nil
end

class TestService < Alumna::MemoryAdapter
  def initialize
    super(TestSchema)
    before Authenticate
    before Alumna.validate(TestSchema), on: :write
    after AfterLogger
  end
end

class AfterFailService < Alumna::MemoryAdapter
  def initialize
    super(TestSchema)
    before Authenticate
    before Alumna.validate(TestSchema), on: :write
    after AfterLogger
    after Alumna::Rule.new { |_ctx| Alumna::ServiceError.internal("after failed") }
    error Alumna::Rule.new { |ctx| ctx.http.headers["X-Service-Error"] = "svc-456"; nil }
  end
end

class CorsService < Alumna::MemoryAdapter
  def initialize
    super()
    before Alumna.cors(origins: ["https://example.com"]),
      on: [:find, :get, :create, :update, :patch, :remove, :options]
  end
end

# We instantiate the App globally so it can be shared across tests, just like before.
# But we never bind it to a port.
APP = Alumna::App.new.tap do |app|
  app.error ErrorLogger
  app.use("/test", TestService.new)
  app.use("/after-stop", AfterFailService.new)
  app.use("/cors-test", CorsService.new)
  app.use "/block", Alumna.memory(TestSchema) {
    before Authenticate
    before Alumna.validate(TestSchema), on: :write
    after AfterLogger
  }
end

# A helper to return our new AppClient with pre-configured headers
def authenticated_client
  Alumna::Testing::AppClient.new(APP).tap do |c|
    c.default_headers["Authorization"] = "Bearer test-token"
    c.default_headers["Content-Type"] = "application/json"
  end
end

describe "Alumna System Integration" do
  it "initially returns empty array" do
    res = authenticated_client.get("/test")
    res.status.should eq(200)
    res.json.as_a.should be_empty
  end

  it "creates with 201 and auto-generated id" do
    res = authenticated_client.post("/test", body: %({"title":"Create 201"}))
    res.status.should eq(201)
    data = res.json
    data["id"].as_s.should match(/^\d+$/)
    data["title"].as_s.should eq("Create 201")
  end

  it "ignores client-supplied id on create" do
    res = authenticated_client.post("/test", body: %({"id":"999","title":"Ignore ID"}))
    res.json["id"].as_s.should_not eq("999")
  end

  it "lists all records" do
    authenticated_client.post("/test", body: %({"title":"List Test"}))
    authenticated_client.get("/test").body.should contain("List Test")
  end

  it "filters find by query params" do
    authenticated_client.post("/test", body: %({"title":"Filter A","content":"x"}))
    authenticated_client.post("/test", body: %({"title":"Filter B","content":"y"}))
    res = authenticated_client.get("/test?title=Filter%20A")
    arr = res.json.as_a
    arr.size.should eq(1)
    arr[0]["title"].as_s.should eq("Filter A")
  end

  it "gets a specific record" do
    id = authenticated_client.post("/test", body: %({"title":"Get Test"})).json["id"].as_s
    res = authenticated_client.get("/test/#{id}")
    res.status.should eq(200)
    res.json["title"].as_s.should eq("Get Test")
  end

  it "returns 404 for unknown get" do
    authenticated_client.get("/test/99999").status.should eq(404)
  end

  it "update replaces entire record" do
    id = authenticated_client.post("/test", body: %({"title":"Orig","content":"keep"})).json["id"].as_s
    data = authenticated_client.put("/test/#{id}", body: %({"title":"Replaced"})).json
    data["title"].as_s.should eq("Replaced")
    data["content"]?.should be_nil
  end

  it "patch merges fields without sending required title" do
    id = authenticated_client.post("/test", body: %({"title":"Patch","content":"Orig"})).json["id"].as_s
    data = authenticated_client.patch("/test/#{id}", body: %({"content":"Patched"})).json
    data["title"].as_s.should eq("Patch")
    data["content"].as_s.should eq("Patched")
  end

  it "update and patch cannot change id" do
    id = authenticated_client.post("/test", body: %({"title":"ID Test"})).json["id"].as_s
    res = authenticated_client.patch("/test/#{id}", body: %({"id":"hacked","title":"ID Test"}))
    res.json["id"].as_s.should eq(id)
  end

  it "returns 404 for update on missing id" do
    authenticated_client.put("/test/99999", body: %({"title":"x"})).status.should eq(404)
  end

  it "deletes and returns removed:true" do
    id = authenticated_client.post("/test", body: %({"title":"Del"})).json["id"].as_s
    authenticated_client.delete("/test/#{id}").json["removed"].as_bool.should be_true
    authenticated_client.get("/test/#{id}").status.should eq(404)
  end

  it "delete non-existent returns removed:false" do
    authenticated_client.delete("/test/99999").json["removed"].as_bool.should be_false
  end

  it "rejects missing token" do
    Alumna::Testing::AppClient.new(APP).get("/test").status.should eq(401)
  end

  it "rejects wrong token" do
    client = Alumna::Testing::AppClient.new(APP)
    client.default_headers["Authorization"] = "Bearer wrong"
    client.get("/test").status.should eq(401)
  end

  it "auth header is case-insensitive" do
    client = Alumna::Testing::AppClient.new(APP)
    client.default_headers["AUTHORIZATION"] = "Bearer test-token"
    client.get("/test").status.should eq(200)
  end

  it "requires title" do
    res = authenticated_client.post("/test", body: %({"content":"x"}))
    res.status.should eq(422)
    res.json["details"]["title"].as_s.should contain("required")
  end

  it "validates min_length" do
    authenticated_client.post("/test", body: %({"title":""})).json["details"]["title"].as_s.should contain("at least 1")
  end

  it "validates max_length" do
    long = "a" * 101
    authenticated_client.post("/test", body: %({"title":"#{long}"})).json["details"]["title"].as_s.should contain("at most 100")
  end

  it "validates type" do
    authenticated_client.post("/test", body: %({"title":123})).json["details"]["title"].as_s.should contain("string")
  end

  it "allows optional content to be omitted" do
    authenticated_client.post("/test", body: %({"title":"Optional"})).status.should eq(201)
  end

  it "validation runs on update but not on get" do
    id = authenticated_client.post("/test", body: %({"title":"V"})).json["id"].as_s
    authenticated_client.get("/test/#{id}").status.should eq(200)
    authenticated_client.put("/test/#{id}", body: %({"content":"x"})).status.should eq(422)
  end

  it "returns validation details structure" do
    body = authenticated_client.post("/test", body: %({})).json
    body["error"].as_s.should eq("Validation failed")
    body["details"].as_h.has_key?("title").should be_true
  end

  it "after-rule adds X-Request-ID header" do
    res = authenticated_client.get("/test")
    res.headers["X-Request-ID"]?.should_not be_nil
    res.headers["X-Request-ID"].size.should eq(16)
  end

  it "error-rule adds X-Error-ID header on auth failure" do
    res = Alumna::Testing::AppClient.new(APP).get("/test")
    res.status.should eq(401)
    res.headers["X-Error-ID"]?.should eq("err-123")
  end

  it "after-rule does not run on error" do
    res = Alumna::Testing::AppClient.new(APP).get("/test")
    res.headers["X-Request-ID"]?.should be_nil
  end

  it "runs app error rules when an after-rule stops" do
    res = authenticated_client.get("/after-stop")
    res.status.should eq(500)
    res.headers["X-Error-ID"]?.should eq("err-123")      # app-level
    res.headers["X-Service-Error"]?.should eq("svc-456") # service-level
    res.headers["X-Request-ID"]?.should_not be_nil       # AfterLogger ran before the stop
    res.json["error"].as_s.should eq("after failed")
  end

  it "CORS preflight returns 204 with empty body" do
    client = Alumna::Testing::AppClient.new(APP)
    client.default_headers["Origin"] = "https://example.com"
    client.default_headers["Access-Control-Request-Method"] = "POST"

    res = client.options("/cors-test")
    res.status.should eq(204)
    res.body.should be_empty
    res.headers["Access-Control-Allow-Origin"].should eq("https://example.com")
    res.headers["Access-Control-Allow-Methods"].should contain("POST")
  end

  it "works with block-initialized service" do
    res = authenticated_client.get("/block")
    res.status.should eq(200)
    res.headers["X-Request-ID"]?.should_not be_nil
  end
end
