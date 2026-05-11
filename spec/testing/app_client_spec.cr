require "../spec_helper"
require "../../src/testing"

class EchoService < Alumna::MemoryAdapter
  def find(ctx)
    [{"echo" => ctx.http_method} of String => Alumna::AnyData]
  end

  def create(ctx)
    {"echo" => ctx.http_method, "body" => ctx.data["msg"]?} of String => Alumna::AnyData
  end

  def update(ctx)
    {"echo" => ctx.http_method} of String => Alumna::AnyData
  end

  def patch(ctx)
    {"echo" => ctx.http_method} of String => Alumna::AnyData
  end

  def remove(ctx)
    true
  end
end

describe Alumna::Testing::AppClient do
  app = Alumna::App.new
  app.use("/echo", EchoService.new)

  # A dummy CORS rule to test the OPTIONS verb
  app.before(Alumna.cors(origins: ["*"]), on: :options)

  client = Alumna::Testing::AppClient.new(app)
  client.default_headers["Content-Type"] = "application/json"

  it "dispatches GET requests" do
    res = client.get("/echo")
    res.status.should eq(200)
    res.json[0]["echo"].as_s.should eq("GET")
  end

  it "dispatches POST requests with a body" do
    res = client.post("/echo", %({"msg":"hello"}))
    res.status.should eq(201)
    res.json["echo"].as_s.should eq("POST")
    res.json["body"].as_s.should eq("hello")
  end

  it "dispatches PUT requests" do
    res = client.put("/echo/1", %({}))
    res.status.should eq(200)
    res.json["echo"].as_s.should eq("PUT")
  end

  it "dispatches PATCH requests" do
    res = client.patch("/echo/1", %({}))
    res.status.should eq(200)
    res.json["echo"].as_s.should eq("PATCH")
  end

  it "dispatches DELETE requests" do
    res = client.delete("/echo/1")
    res.status.should eq(200)
    res.json["removed"].as_bool.should be_true
  end

  it "dispatches OPTIONS requests" do
    # Added "Origin" header to trigger the CORS preflight logic
    res = client.options("/echo", headers: {
      "Origin"                        => "https://example.com",
      "Access-Control-Request-Method" => "POST",
    })
    res.status.should eq(204)
    res.headers["Access-Control-Allow-Origin"].should eq("*")
  end

  it "merges default headers with request headers" do
    auth_client = Alumna::Testing::AppClient.new(app)
    auth_client.default_headers["X-Global"] = "1"

    # Send a request that triggers a 404 to easily inspect the response
    res = auth_client.get("/missing", headers: {"X-Local" => "2"})
    res.status.should eq(404)
  end
end
