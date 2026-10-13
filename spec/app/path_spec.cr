require "../spec_helper"
require "../../src/testing"

describe "App path normalization" do
  it "treats trailing slash as same route" do
    app = Alumna::App.new
    svc = Alumna::MemoryAdapter.new
    app.use("/test/", svc) # normalized to /test

    app.services.has_key?("/test").should be_true
    app.services.has_key?("/test/").should be_false
  end

  it "raises on duplicate mount" do
    app = Alumna::App.new
    app.use("/items", Alumna::MemoryAdapter.new)
    expect_raises(ArgumentError, /already mounted/) do
      app.use("/items/", Alumna::MemoryAdapter.new)
    end
  end

  it "rejects paths without leading slash" do
    app = Alumna::App.new
    expect_raises(ArgumentError, /must start with/) do
      app.use("items", Alumna::MemoryAdapter.new)
    end
  end

  it "runs a use block on the service, then mounts it" do
    app = Alumna::App.new
    svc = Alumna::MemoryAdapter.new
    app.use("/items", svc) do
      before on: :find do |_ctx|
        Alumna::ServiceError.unauthorized("from-block")
      end
    end

    app.services["/items"]?.should be(svc)
    client = Alumna::Testing::AppClient.new(app)
    res = client.get("/items")
    res.status.should eq(401)
    res.body.should contain("from-block")
  end
end
