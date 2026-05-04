require "../spec_helper"
require "http/client"
require "json"

TEST_PORT = 3001

TestSchema = Alumna::Schema.new
  .str("title", required_on: [:create, :update], min_length: 1, max_length: 100)
  .str("content", required: false)

Authenticate = Alumna::Rule.new do |ctx|
  token = ctx.headers["authorization"]?
  token == "Bearer test-token" ? Alumna::RuleResult.continue : Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized)
end

AfterLogger = Alumna::Rule.new do |ctx|
  ctx.http.headers["X-Request-ID"] = Random::Secure.hex(8)
  Alumna::RuleResult.continue
end

ErrorLogger = Alumna::Rule.new do |ctx|
  ctx.http.headers["X-Error-ID"] = "err-123"
  Alumna::RuleResult.continue
end

class TestService < Alumna::MemoryAdapter
  def initialize
    super("/test", TestSchema)
    before Authenticate
    before Alumna.validate(TestSchema), only: [:create, :update, :patch]
    after AfterLogger
  end
end

class AfterFailService < Alumna::MemoryAdapter
  def initialize
    super("/after-stop", TestSchema)
    before Authenticate
    before Alumna.validate(TestSchema), only: [:create, :update, :patch]
    after AfterLogger
    # this after-rule forces the failure path in App#dispatch
    after Alumna::Rule.new { |ctx|
      Alumna::RuleResult.stop(Alumna::ServiceError.internal("after failed"))
    }
    # service-level error hook
    error Alumna::Rule.new { |ctx|
      ctx.http.headers["X-Service-Error"] = "svc-456"
      Alumna::RuleResult.continue
    }
  end
end

def authenticated_client
  HTTP::Client.new("localhost", TEST_PORT).tap do |c|
    c.before_request do |r|
      r.headers["Authorization"] = "Bearer test-token"
      r.headers["Content-Type"] = "application/json"
    end
  end
end

def json(body)
  JSON.parse(body)
end

describe "Alumna System Integration" do
  before_all do
    app = Alumna::App.new
    app.error ErrorLogger
    app.use("/test", TestService.new)
    app.use("/after-stop", AfterFailService.new)
    spawn { app.listen(TEST_PORT) }
    sleep 0.3.seconds
  end

  it "initially returns empty array" do
    res = authenticated_client.get("/test")
    res.status_code.should eq(200)
    json(res.body).as_a.should be_empty
  end

  it "creates with 201 and auto-generated id" do
    res = authenticated_client.post("/test", body: %({"title":"Create 201"}))
    res.status_code.should eq(201)
    data = json(res.body)
    data["id"].as_s.should match(/^\d+$/)
    data["title"].as_s.should eq("Create 201")
  end

  it "ignores client-supplied id on create" do
    res = authenticated_client.post("/test", body: %({"id":"999","title":"Ignore ID"}))
    json(res.body)["id"].as_s.should_not eq("999")
  end

  it "lists all records" do
    authenticated_client.post("/test", body: %({"title":"List Test"}))
    authenticated_client.get("/test").body.should contain("List Test")
  end

  it "filters find by query params" do
    authenticated_client.post("/test", body: %({"title":"Filter A","content":"x"}))
    authenticated_client.post("/test", body: %({"title":"Filter B","content":"y"}))
    res = authenticated_client.get("/test?title=Filter%20A")
    arr = json(res.body).as_a
    arr.size.should eq(1)
    arr[0]["title"].as_s.should eq("Filter A")
  end

  it "gets a specific record" do
    id = json(authenticated_client.post("/test", body: %({"title":"Get Test"})).body)["id"].as_s
    res = authenticated_client.get("/test/#{id}")
    res.status_code.should eq(200)
    json(res.body)["title"].as_s.should eq("Get Test")
  end

  it "returns 404 for unknown get" do
    authenticated_client.get("/test/99999").status_code.should eq(404)
  end

  it "update replaces entire record" do
    id = json(authenticated_client.post("/test", body: %({"title":"Orig","content":"keep"})).body)["id"].as_s
    data = json(authenticated_client.put("/test/#{id}", body: %({"title":"Replaced"})).body)
    data["title"].as_s.should eq("Replaced")
    data["content"]?.should be_nil
  end

  it "patch merges fields without sending required title" do
    id = json(authenticated_client.post("/test", body: %({"title":"Patch","content":"Orig"})).body)["id"].as_s
    data = json(authenticated_client.patch("/test/#{id}", body: %({"content":"Patched"})).body)
    data["title"].as_s.should eq("Patch")
    data["content"].as_s.should eq("Patched")
  end

  it "update and patch cannot change id" do
    id = json(authenticated_client.post("/test", body: %({"title":"ID Test"})).body)["id"].as_s
    res = authenticated_client.patch("/test/#{id}", body: %({"id":"hacked","title":"ID Test"}))
    json(res.body)["id"].as_s.should eq(id)
  end

  it "returns 404 for update on missing id" do
    authenticated_client.put("/test/99999", body: %({"title":"x"})).status_code.should eq(404)
  end

  it "deletes and returns removed:true" do
    id = json(authenticated_client.post("/test", body: %({"title":"Del"})).body)["id"].as_s
    json(authenticated_client.delete("/test/#{id}").body)["removed"].as_bool.should be_true
    authenticated_client.get("/test/#{id}").status_code.should eq(404)
  end

  it "delete non-existent returns removed:false" do
    json(authenticated_client.delete("/test/99999").body)["removed"].as_bool.should be_false
  end

  it "rejects missing token" do
    HTTP::Client.new("localhost", TEST_PORT).get("/test").status_code.should eq(401)
  end

  it "rejects wrong token" do
    client = HTTP::Client.new("localhost", TEST_PORT)
    client.before_request { |r| r.headers["Authorization"] = "Bearer wrong" }
    client.get("/test").status_code.should eq(401)
  end

  it "auth header is case-insensitive" do
    client = HTTP::Client.new("localhost", TEST_PORT)
    client.before_request { |r| r.headers["AUTHORIZATION"] = "Bearer test-token" }
    client.get("/test").status_code.should eq(200)
  end

  it "requires title" do
    res = authenticated_client.post("/test", body: %({"content":"x"}))
    res.status_code.should eq(422)
    json(res.body)["details"]["title"].as_s.should contain("required")
  end

  it "validates min_length" do
    json(authenticated_client.post("/test", body: %({"title":""})).body)["details"]["title"].as_s.should contain("at least 1")
  end

  it "validates max_length" do
    long = "a" * 101
    json(authenticated_client.post("/test", body: %({"title":"#{long}"})).body)["details"]["title"].as_s.should contain("at most 100")
  end

  it "validates type" do
    json(authenticated_client.post("/test", body: %({"title":123})).body)["details"]["title"].as_s.should contain("string")
  end

  it "allows optional content to be omitted" do
    authenticated_client.post("/test", body: %({"title":"Optional"})).status_code.should eq(201)
  end

  it "validation runs on update but not on get" do
    id = json(authenticated_client.post("/test", body: %({"title":"V"})).body)["id"].as_s
    authenticated_client.get("/test/#{id}").status_code.should eq(200)
    authenticated_client.put("/test/#{id}", body: %({"content":"x"})).status_code.should eq(422)
  end

  it "returns validation details structure" do
    body = json(authenticated_client.post("/test", body: %({})).body)
    body["error"].as_s.should eq("Validation failed")
    body["details"].as_h.has_key?("title").should be_true
  end

  it "after-rule adds X-Request-ID header" do
    res = authenticated_client.get("/test")
    res.headers["X-Request-ID"]?.should_not be_nil
    res.headers["X-Request-ID"].size.should eq(16)
  end

  it "error-rule adds X-Error-ID header on auth failure" do
    res = HTTP::Client.new("localhost", TEST_PORT).get("/test")
    res.status_code.should eq(401)
    res.headers["X-Error-ID"]?.should eq("err-123")
  end

  it "after-rule does not run on error" do
    res = HTTP::Client.new("localhost", TEST_PORT).get("/test")
    res.headers["X-Request-ID"]?.should be_nil
  end

  it "runs app error rules when an after-rule stops" do
    res = authenticated_client.get("/after-stop")
    res.status_code.should eq(500)
    res.headers["X-Error-ID"]?.should eq("err-123")      # app-level
    res.headers["X-Service-Error"]?.should eq("svc-456") # service-level
    # AfterLogger ran before the stop, so the header is present
    res.headers["X-Request-ID"]?.should_not be_nil
    json(res.body)["error"].as_s.should eq("after failed")
  end
end
