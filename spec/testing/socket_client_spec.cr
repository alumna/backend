require "../spec_helper"
require "../../src/testing"

describe Alumna::Testing::SocketClient do
  it "dispatches frames without listen" do
    app = Alumna::App.new
    app.use("/items", Alumna.memory)
    client = Alumna::Testing::SocketClient.new(app)
    created = client.call("create", "/items", data: Alumna.hash(name: "a"))
    created["result"].as(Hash)["name"].should eq("a")
    id = created["result"].as(Hash)["id"].as(String)
    got = client.call("get", "/items", id: "g", resource_id: id)
    got["id"].should eq("g")
    got["result"].as(Hash)["name"].should eq("a")
    found = client.call("find", "/items", params: {"$limit" => 1_i64} of String => Alumna::AnyData)
    found["result"].as(Array).size.should eq(1)
    client.connection_id.should eq(client.session.id)
    client.close
  end

  it "sends a raw JSON frame" do
    app = Alumna::App.new
    app.use("/items", Alumna.memory)
    client = Alumna::Testing::SocketClient.new(app, HTTP::Headers{"X-Test" => "1"})
    reply = client.send(%({"id":"r","method":"find","path":"/items"}))
    reply["id"].should eq("r")
    client.close
  end
end
