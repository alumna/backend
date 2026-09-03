require "../spec_helper"
require "json"
require "../../src/testing"

TestSchema = Alumna::Schema.new
  .str("id", read_only: true)
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
    res.json_array.should be_empty
  end

  it "creates with 201 and auto-generated id" do
    res = authenticated_client.post("/test", body: %({"title":"Create 201"}))
    res.status.should eq(201)
    data = res.json_hash
    data["id"].as(String).should match(/^\d+$/)
    data["title"].should eq("Create 201")
  end

  it "rejects client-supplied id on create because it is read-only" do
    res = authenticated_client.post("/test", body: %({"id":"999","title":"Ignore ID"}))
    res.status.should eq(422)
    res.json_hash.dig_str("details.id").should eq("is read-only")
  end

  it "lists all records" do
    authenticated_client.post("/test", body: %({"title":"List Test"}))
    authenticated_client.get("/test").body.should contain("List Test")
  end

  it "filters find by query params" do
    authenticated_client.post("/test", body: %({"title":"Filter A","content":"x"}))
    authenticated_client.post("/test", body: %({"title":"Filter B","content":"y"}))
    res = authenticated_client.get("/test?title=Filter%20A")
    arr = res.json_array
    arr.size.should eq(1)
    arr[0].as(Hash)["title"].should eq("Filter A")
  end

  it "gets a specific record" do
    id = authenticated_client.post("/test", body: %({"title":"Get Test"})).json_hash["id"].as(String)
    res = authenticated_client.get("/test/#{id}")
    res.status.should eq(200)
    res.json_hash["title"].should eq("Get Test")
  end

  it "returns 404 for unknown get" do
    authenticated_client.get("/test/99999").status.should eq(404)
  end

  it "update replaces entire record" do
    id = authenticated_client.post("/test", body: %({"title":"Orig","content":"keep"})).json_hash["id"].as(String)
    data = authenticated_client.put("/test/#{id}", body: %({"title":"Replaced"})).json_hash
    data["title"].should eq("Replaced")
    data["content"]?.should be_nil
  end

  it "patch merges fields without sending required title" do
    id = authenticated_client.post("/test", body: %({"title":"Patch","content":"Orig"})).json_hash["id"].as(String)
    data = authenticated_client.patch("/test/#{id}", body: %({"content":"Patched"})).json_hash
    data["title"].should eq("Patch")
    data["content"].should eq("Patched")
  end

  it "accepts reserved $unset path on a strict schema patch" do
    id = authenticated_client.post("/test", body: %({"title":"Unset path","content":"keep"})).json_hash["id"].as(String)
    res = authenticated_client.patch("/test/#{id}", body: %({"$unset":"content"}))
    res.status.should eq(200)
    data = res.json_hash
    # MemoryAdapter does not implement $unset: the key stays, the field is not removed.
    data["$unset"].should eq("content")
    data["content"].should eq("keep")
  end

  it "accepts reserved $unset list on a strict schema patch" do
    id = authenticated_client.post("/test", body: %({"title":"Unset list","content":"keep"})).json_hash["id"].as(String)
    res = authenticated_client.patch("/test/#{id}", body: %({"$unset":["content"]}))
    res.status.should eq(200)
  end

  it "still returns 422 for unknown real fields when $unset is present" do
    id = authenticated_client.post("/test", body: %({"title":"Unset extra"})).json_hash["id"].as(String)
    res = authenticated_client.patch("/test/#{id}", body: %({"$unset":"content","nope":"x"}))
    res.status.should eq(422)
    res.json_hash.dig_str("details.nope").should eq("is not allowed")
  end

  it "update and patch cannot change id because it is read-only" do
    id = authenticated_client.post("/test", body: %({"title":"ID Test"})).json_hash["id"].as(String)
    res = authenticated_client.patch("/test/#{id}", body: %({"id":"hacked","title":"ID Test"}))
    res.status.should eq(422)
    res.json_hash.dig_str("details.id").should eq("is read-only")
  end

  it "returns 404 for update on missing id" do
    authenticated_client.put("/test/99999", body: %({"title":"x"})).status.should eq(404)
  end

  it "deletes and returns 204 No Content" do
    id = authenticated_client.post("/test", body: %({"title":"Del"})).json_hash["id"].as(String)
    res = authenticated_client.delete("/test/#{id}")
    res.status.should eq(204)
    res.body.should be_empty
    authenticated_client.get("/test/#{id}").status.should eq(404)
  end

  it "delete non-existent returns 404" do
    authenticated_client.delete("/test/99999").status.should eq(404)
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
    res.json_hash.dig_str("details.title").should contain("required")
  end

  it "validates min_length" do
    authenticated_client.post("/test", body: %({"title":""})).json_hash.dig_str("details.title").should contain("at least 1")
  end

  it "validates max_length" do
    long = "a" * 101
    authenticated_client.post("/test", body: %({"title":"#{long}"})).json_hash.dig_str("details.title").should contain("at most 100")
  end

  it "validates type" do
    authenticated_client.post("/test", body: %({"title":123})).json_hash.dig_str("details.title").should contain("string")
  end

  it "allows optional content to be omitted" do
    authenticated_client.post("/test", body: %({"title":"Optional"})).status.should eq(201)
  end

  it "validation runs on update but not on get" do
    id = authenticated_client.post("/test", body: %({"title":"V"})).json_hash["id"].as(String)
    authenticated_client.get("/test/#{id}").status.should eq(200)
    authenticated_client.put("/test/#{id}", body: %({"content":"x"})).status.should eq(422)
  end

  it "returns validation details structure" do
    body = authenticated_client.post("/test", body: %({})).json_hash
    body["error"].should eq("Validation failed")
    body["details"].as(Hash).has_key?("title").should be_true
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
    res.json_hash["error"].should eq("after failed")
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
