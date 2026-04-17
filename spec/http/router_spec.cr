require "../spec_helper"
require "http/client"

# ── Test application setup ────────────────────────────────────────────────────
#
# We spin up a real HTTP::Server on a random OS-assigned port once for the
# entire suite. All specs share the same server and service instance, so
# insertion order matters for the few tests that read back what they wrote.
# Each describe block that mutates state documents its assumptions clearly.

ItemSchema = Alumna::Schema.new
  .field("name", Alumna::FieldType::Str, required: true, min_length: 1)
  .field("role", Alumna::FieldType::Str, required: false)

# A minimal service with one before rule that checks a hardcoded token,
# so we can also test that rule-generated errors propagate through the HTTP layer.
class ItemService < Alumna::MemoryAdapter
  def initialize
    super("/items", ItemSchema)

    self.before(Alumna::Rule.new do |ctx|
      token = ctx.headers["authorization"]?
      if token == "valid-token"
        Alumna::RuleResult.continue
      else
        Alumna::RuleResult.stop(Alumna::ServiceError.unauthorized("Invalid or missing token"))
      end
    end)

    self.before(
      Alumna::Rule.new do |ctx|
        errors = ItemSchema.validate(ctx.data)
        if errors.empty?
          Alumna::RuleResult.continue
        else
          details = errors.each_with_object({} of String => String) do |e, h|
            h[e.field] = e.message
          end
          Alumna::RuleResult.stop(Alumna::ServiceError.unprocessable("Validation failed", details))
        end
      end,
      only: [
        Alumna::ServiceMethod::Create,
        Alumna::ServiceMethod::Update,
      ]
    )
  end
end

# ── Server lifecycle ──────────────────────────────────────────────────────────

app = Alumna::App.new
app.use("/items", ItemService.new)

router = Alumna::Http::Router.new(app)
server = HTTP::Server.new { |ctx| router.handle(ctx) }
PORT = 3000
server.bind_tcp("127.0.0.1", PORT)

spawn { server.listen }
Fiber.yield # let the server start before the first spec runs

# ── Request helpers ───────────────────────────────────────────────────────────

private AUTH = {"Authorization" => "valid-token"}

private def get(path, headers : Hash(String, String) = {} of String => String)
  HTTP::Client.get("http://127.0.0.1:#{PORT}#{path}", headers: HTTP::Headers.new.tap { |h|
    headers.each { |k, v| h[k] = v }
  })
end

private def post(path, body : String, headers : Hash(String, String) = {} of String => String)
  h = HTTP::Headers{"Content-Type" => "application/json"}.tap { |h|
    headers.each { |k, v| h[k] = v }
  }
  HTTP::Client.post("http://127.0.0.1:#{PORT}#{path}", headers: h, body: body)
end

private def put(path, body : String, headers : Hash(String, String) = {} of String => String)
  h = HTTP::Headers{"Content-Type" => "application/json"}.tap { |h|
    headers.each { |k, v| h[k] = v }
  }
  HTTP::Client.put("http://127.0.0.1:#{PORT}#{path}", headers: h, body: body)
end

private def patch(path, body : String, headers : Hash(String, String) = {} of String => String)
  h = HTTP::Headers{"Content-Type" => "application/json"}.tap { |h|
    headers.each { |k, v| h[k] = v }
  }
  HTTP::Client.patch("http://127.0.0.1:#{PORT}#{path}", headers: h, body: body)
end

private def delete(path, headers : Hash(String, String) = {} of String => String)
  HTTP::Client.delete("http://127.0.0.1:#{PORT}#{path}", headers: HTTP::Headers.new.tap { |h|
    headers.each { |k, v| h[k] = v }
  })
end

# ─────────────────────────────────────────────────────────────────────────────

describe "Router integration" do
  # ── Unknown path ──────────────────────────────────────────────────────────────

  describe "unknown path" do
    it "returns 404 for a path with no registered service" do
      response = get("/unknown", AUTH)
      response.status_code.should eq(404)
    end
  end

  # ── Method not allowed ────────────────────────────────────────────────────────

  describe "method not allowed" do
    it "returns 405 for POST with an id segment" do
      response = post("/items/1", "{}", AUTH)
      response.status_code.should eq(405)
    end
  end

  # ── Authentication rule ───────────────────────────────────────────────────────

  describe "authentication rule" do
    it "returns 401 when the authorization header is missing" do
      response = get("/items")
      response.status_code.should eq(401)
    end

    it "returns 401 when the authorization header is wrong" do
      response = get("/items", {"Authorization" => "bad-token"})
      response.status_code.should eq(401)
    end

    it "returns 401 with an error body" do
      response = get("/items")
      body = JSON.parse(response.body)
      body["error"].as_s.should eq("Invalid or missing token")
    end
  end

  # ── Verb → ServiceMethod mapping ──────────────────────────────────────────────

  describe "verb → method mapping" do
    it "GET /items maps to find (returns an array)" do
      response = get("/items", AUTH)
      response.status_code.should eq(200)
      JSON.parse(response.body).as_a?.should_not be_nil
    end

    it "POST /items maps to create (returns 201)" do
      response = post("/items", %|{"name":"Widget"}|, AUTH)
      response.status_code.should eq(201)
    end

    it "GET /items/:id maps to get" do
      # create a record first so we have a valid id
      post("/items", %|{"name":"Gadget"}|, AUTH)
      response = get("/items/1", AUTH)
      response.status_code.should eq(200)
      JSON.parse(response.body)["name"].as_s.should eq("Widget")
    end

    it "PUT /items/:id maps to update" do
      response = put("/items/1", %|{"name":"Widget Pro"}|, AUTH)
      response.status_code.should eq(200)
      JSON.parse(response.body)["name"].as_s.should eq("Widget Pro")
    end

    it "PATCH /items/:id maps to patch" do
      response = patch("/items/1", %|{"role":"admin"}|, AUTH)
      response.status_code.should eq(200)
      body = JSON.parse(response.body)
      body["name"].as_s.should eq("Widget Pro") # original field preserved
      body["role"].as_s.should eq("admin")      # new field added
    end

    it "DELETE /items/:id maps to remove" do
      # create a fresh record to delete so we don't depend on id "1" still existing
      created = post("/items", %|{"name":"ToDelete"}|, AUTH)
      id = JSON.parse(created.body)["id"].as_s
      response = delete("/items/#{id}", AUTH)
      response.status_code.should eq(200)
      JSON.parse(response.body)["removed"].as_bool.should be_true
    end
  end

  # ── Response Content-Type ─────────────────────────────────────────────────────

  describe "response Content-Type" do
    it "defaults to application/json" do
      response = get("/items", AUTH)
      response.content_type.should eq("application/json")
    end

    it "returns application/msgpack when Accept header requests it" do
      h = AUTH.merge({"Accept" => "application/msgpack"})
      response = get("/items", h)
      response.content_type.should eq("application/msgpack")
    end
  end

  # ── Query param filtering ─────────────────────────────────────────────────────

  describe "query param filtering" do
    it "passes query params to the service and filters results" do
      post("/items", %|{"name":"Alpha","role":"reader"}|, AUTH)
      post("/items", %|{"name":"Beta","role":"editor"}|, AUTH)

      response = get("/items?role=reader", AUTH)
      results = JSON.parse(response.body).as_a
      results.all? { |r| r["role"].as_s == "reader" }.should be_true
    end
  end

  # ── Validation error (422) ────────────────────────────────────────────────────

  describe "validation errors" do
    it "returns 422 when the request body fails schema validation" do
      response = post("/items", %|{"name":""}|, AUTH)
      response.status_code.should eq(422)
    end

    it "returns an error body with field-level details" do
      response = post("/items", %|{"name":""}|, AUTH)
      body = JSON.parse(response.body)
      body["error"].as_s.should eq("Validation failed")
      body["details"].as_h.has_key?("name").should be_true
    end
  end

  # ── 404 from service method ───────────────────────────────────────────────────

  describe "service-level 404" do
    it "returns 404 when getting a non-existent record" do
      response = get("/items/99999", AUTH)
      response.status_code.should eq(404)
    end
  end

  # ── Serializer negotiation edge cases ──────────────────────────────────────────

  describe "serializer negotiation" do
    it "falls back to app default when Content-Type is missing" do
      # post without Content-Type header — router should use JSON (app default)
      client = HTTP::Client.new("127.0.0.1", PORT)
      headers = HTTP::Headers{"Authorization" => "valid-token"}
      response = client.post("/items", headers: headers, body: %|{"name":"NoCT"}|)
      response.status_code.should eq(201)
      JSON.parse(response.body)["name"].as_s.should eq("NoCT")
    end

    it "uses input serializer for output when Accept is missing" do
      # GET with Content-Type: msgpack but no Accept — output should be msgpack
      headers = AUTH.merge({"Content-Type" => "application/msgpack"})
      response = get("/items", headers)
      response.status_code.should eq(200)
      response.content_type.should eq("application/msgpack")
    end

    it "resolves input and output serializers independently" do
      # JSON in, MessagePack out
      headers = AUTH.merge({
        "Content-Type" => "application/json",
        "Accept"       => "application/msgpack",
      })
      response = post("/items", %|{"name":"Indep"}|, headers)
      response.status_code.should eq(201)
      response.content_type.should eq("application/msgpack")
    end
  end

  # ── Path matching edge cases ───────────────────────────────────────────────────

  describe "path matching" do
    it "returns 404 for trailing slash on id segment" do
      # /items/1/ → id would be "1/", which contains '/', so no match
      response = get("/items/1/", AUTH)
      response.status_code.should eq(404)
    end

    it "returns 404 for nested path segments" do
      response = get("/items/1/extra", AUTH)
      response.status_code.should eq(404)
    end
  end

  # ── Body parsing edge cases ────────────────────────────────────────────────────

  describe "body parsing" do
    it "treats missing body as empty hash, not nil" do
      client = HTTP::Client.new("127.0.0.1", PORT)
      headers = HTTP::Headers{
        "Authorization" => "valid-token",
        "Content-Type"  => "application/json",
      }
      # POST with headers but no body — should hit validation, not crash
      response = client.post("/items", headers: headers)
      response.status_code.should eq(422)
      JSON.parse(response.body)["error"].as_s.should eq("Validation failed")
    end
  end
end
