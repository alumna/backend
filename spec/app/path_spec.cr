require "../spec_helper"

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
end
