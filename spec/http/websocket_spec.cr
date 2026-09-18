require "../spec_helper"
require "../../src/testing"
require "http/web_socket"
require "socket"

private RFC_KEY    = "dGhlIHNhbXBsZSBub25jZQ=="
private RFC_ACCEPT = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

class ProviderProbe < Alumna::MemoryAdapter
  def find(ctx)
    [{"provider" => ctx.provider} of String => Alumna::AnyData]
  end
end

class BoomSession < Alumna::Http::WebSocketSession
  def process_frame(text : String) : Hash(String, Alumna::AnyData)
    raise "boom"
  end
end

private def wait_for_port(host : String, port : Int32, timeout : Time::Span = 5.seconds)
  deadline = Time.instant + timeout
  loop do
    begin
      TCPSocket.new(host, port).close
      return
    rescue
      raise "Server did not start within #{timeout}" if Time.instant > deadline
      Fiber.yield
    end
  end
end

describe Alumna::Http do
  it "does not treat a normal HTTP request as a WebSocket upgrade" do
    req = HTTP::Request.new("GET", "/")
    Alumna::Http.websocket_upgrade?(req).should be_false
  end

  it "does not treat a non-websocket Upgrade as a WebSocket upgrade" do
    req = HTTP::Request.new("GET", "/", HTTP::Headers{
      "Upgrade"    => "h2c",
      "Connection" => "Upgrade",
    })
    Alumna::Http.websocket_upgrade?(req).should be_false
  end

  it "requires Connection to include Upgrade" do
    req = HTTP::Request.new("GET", "/", HTTP::Headers{
      "Upgrade"    => "websocket",
      "Connection" => "keep-alive",
    })
    Alumna::Http.websocket_upgrade?(req).should be_false
  end

  it "detects a WebSocket upgrade request" do
    req = HTTP::Request.new("GET", "/", HTTP::Headers{
      "Upgrade"    => "WebSocket",
      "Connection" => "keep-alive, Upgrade",
    })
    Alumna::Http.websocket_upgrade?(req).should be_true
  end
end

private def ws_session(app : Alumna::App = Alumna::App.new)
  unless app.services.has_key?("/items")
    app.use("/items", Alumna.memory)
  end
  Alumna::Http::WebSocketSession.new(
    HTTP::WebSocket.new(IO::Memory.new),
    HTTP::Headers{"Authorization" => "Bearer x"},
    "127.0.0.1",
    app,
  )
end

describe Alumna::Http::WebSocketSession do
  it "sets provider to websocket" do
    session = ws_session
    session.provider.should eq(Alumna::Http::WEBSOCKET_PROVIDER)
    session.provider.should eq("websocket")
    session.remote_ip.should eq("127.0.0.1")
    session.headers["Authorization"].should eq("Bearer x")
  end

  it "creates and gets through dispatch" do
    session = ws_session
    created = session.process_frame(%({"id":"c1","method":"create","path":"/items","data":{"name":"a"}}))
    created["id"].should eq("c1")
    row = created["result"].as(Hash(String, Alumna::AnyData))
    row["name"].should eq("a")
    id = row["id"].as(String)

    got = session.process_frame(%({"id":"g1","method":"get","path":"/items","resource_id":#{id.to_json}}))
    got["id"].should eq("g1")
    got["result"].as(Hash)["name"].should eq("a")
  end

  it "finds through dispatch" do
    session = ws_session
    session.process_frame(%({"id":"1","method":"create","path":"/items","data":{"name":"f"}}))
    found = session.process_frame(%({"id":"2","method":"find","path":"/items"}))
    found["result"].as(Array).size.should be > 0
  end

  it "updates, patches, and removes" do
    session = ws_session
    created = session.process_frame(%({"id":"1","method":"create","path":"/items","data":{"name":"old"}}))
    id = created["result"].as(Hash)["id"].as(String)
    session.process_frame(%({"id":"2","method":"update","path":"/items","resource_id":#{id.to_json},"data":{"name":"new"}}))
    session.process_frame(%({"id":"3","method":"patch","path":"/items","resource_id":#{id.to_json},"data":{"name":"p"}}))
    removed = session.process_frame(%({"id":"4","method":"remove","path":"/items","resource_id":#{id.to_json}}))
    removed.has_key?("result").should be_true
    missing = session.process_frame(%({"id":"5","method":"get","path":"/items","resource_id":#{id.to_json}}))
    missing["error"].as(Hash)["status"].should eq(404)
  end

  it "uses a REST-style path for the resource id" do
    session = ws_session
    created = session.process_frame(%({"id":"1","method":"create","path":"/items","data":{"name":"p"}}))
    id = created["result"].as(Hash)["id"].as(String)
    got = session.process_frame(%({"id":"2","method":"get","path":"/items/#{id}"}))
    got["result"].as(Hash)["name"].should eq("p")
  end

  it "accepts an integer correlation id and $limit as a number" do
    session = ws_session
    session.process_frame(%({"id":1,"method":"create","path":"/items","data":{"name":"n"}}))
    found = session.process_frame(%({"id":2,"method":"find","path":"/items","params":{"$limit":1}}))
    found["id"].should eq(2)
    found["result"].as(Array).size.should eq(1)
  end

  it "copies handshake headers onto the frame context" do
    app = Alumna::App.new
    app.use("/items", Alumna.memory)
    app.services["/items"].before do |ctx|
      ctx.result = {"auth" => ctx.headers["authorization"]?} of String => Alumna::AnyData
      nil
    end
    session = Alumna::Http::WebSocketSession.new(
      HTTP::WebSocket.new(IO::Memory.new),
      HTTP::Headers{"Authorization" => "Bearer x"},
      "127.0.0.1",
      app,
    )
    reply = session.process_frame(%({"id":"h","method":"find","path":"/items"}))
    reply["result"].as(Hash)["auth"].should eq("Bearer x")
  end

  it "sets provider to websocket on the rule context" do
    app = Alumna::App.new
    app.use("/probe", ProviderProbe.new)
    session = Alumna::Http::WebSocketSession.new(
      HTTP::WebSocket.new(IO::Memory.new),
      HTTP::Headers.new,
      "127.0.0.1",
      app,
    )
    reply = session.process_frame(%({"id":"p","method":"find","path":"/probe"}))
    reply["result"].as(Array)[0].as(Hash)["provider"].should eq("websocket")
  end

  it "rejects invalid JSON without raising" do
    reply = ws_session.process_frame("not-json")
    reply.has_key?("id").should be_false
    reply["error"].as(Hash)["message"].should eq("Invalid JSON")
  end

  it "rejects a non-object frame" do
    reply = ws_session.process_frame("[]")
    reply["error"].as(Hash)["message"].should eq("Frame must be a JSON object")
  end

  it "rejects a missing method" do
    reply = ws_session.process_frame(%({"id":"1","path":"/items"}))
    reply["id"].should eq("1")
    reply["error"].as(Hash)["message"].should eq("method is missing")
  end

  it "rejects an unknown method" do
    reply = ws_session.process_frame(%({"id":"1","method":"options","path":"/items"}))
    reply["error"].as(Hash)["status"].should eq(405)
  end

  it "rejects a missing path" do
    reply = ws_session.process_frame(%({"id":"1","method":"find"}))
    reply["error"].as(Hash)["message"].should eq("path is missing")
  end

  it "rejects an unknown service path" do
    reply = ws_session.process_frame(%({"id":"1","method":"find","path":"/nope"}))
    reply["error"].as(Hash)["status"].should eq(404)
  end

  it "rejects data that is not an object" do
    reply = ws_session.process_frame(%({"id":"1","method":"create","path":"/items","data":[]}))
    reply["error"].as(Hash)["message"].should eq("data must be an object")
  end

  it "rejects params that are not an object" do
    reply = ws_session.process_frame(%({"id":"1","method":"find","path":"/items","params":[]}))
    reply["error"].as(Hash)["message"].should eq("params must be an object")
  end

  it "accepts array query params" do
    session = ws_session
    session.process_frame(%({"id":"1","method":"create","path":"/items","data":{"name":"a"}}))
    found = session.process_frame(%({"id":"2","method":"find","path":"/items","params":{"name":["a","b"]}}))
    found.has_key?("result").should be_true
  end

  it "omits data, id, and uses a numeric resource_id" do
    session = ws_session
    created = session.process_frame(%({"method":"create","path":"/items"}))
    created.has_key?("id").should be_false
    id = created["result"].as(Hash)["id"].as(String)
    # Memory ids are "1", "2", ... — numeric JSON is accepted as the resource id string.
    got = session.process_frame(%({"id":"n","method":"get","path":"/items","resource_id":#{id}}))
    got.has_key?("result").should be_true
  end

  it "ignores a non-string resource_id object" do
    reply = ws_session.process_frame(%({"id":"1","method":"find","path":"/items","resource_id":{}}))
    reply.has_key?("result").should be_true
  end

  it "stringifies bool and object query params" do
    reply = ws_session.process_frame(%({"id":"1","method":"find","path":"/items","params":{"flag":true,"meta":{"a":1},"empty":null}}))
    reply.has_key?("result").should be_true
  end

  it "handle_text does not raise" do
    ws_session.handle_text(%({"id":"1","method":"find","path":"/items"}))
  end

  it "handle_binary replies with an error and does not raise" do
    ws_session.handle_binary("hi".to_slice)
  end

  it "rejects an oversized text frame" do
    app = Alumna::App.new
    app.use("/items", Alumna.memory)
    app.max_body_size = 8
    session = Alumna::Http::WebSocketSession.new(
      HTTP::WebSocket.new(IO::Memory.new),
      HTTP::Headers.new,
      "127.0.0.1",
      app,
    )
    reply = session.process_frame(%({"id":"1","method":"find","path":"/items"}))
    reply["error"].as(Hash)["status"].should eq(413)
  end

  it "rejects an oversized binary frame" do
    app = Alumna::App.new
    app.max_body_size = 2
    session = Alumna::Http::WebSocketSession.new(
      HTTP::WebSocket.new(IO::Memory.new),
      HTTP::Headers.new,
      "127.0.0.1",
      app,
    )
    session.handle_binary("abcdef".to_slice)
  end

  it "handle_text after close does not raise" do
    session = ws_session
    session.socket.close
    session.handle_text(%({"id":"1","method":"find","path":"/items"}))
  end

  it "handle_text maps an unexpected exception to an internal error" do
    session = BoomSession.new(
      HTTP::WebSocket.new(IO::Memory.new),
      HTTP::Headers.new,
      "127.0.0.1",
      Alumna::App.new,
    )
    session.handle_text(%({"id":"1","method":"find","path":"/items"}))
  end

  it "reuses one store Hash across frames" do
    app = Alumna::App.new
    app.use("/items", Alumna.memory)
    app.services["/items"].before do |ctx|
      n = ctx.store["n"]?.as?(Int64) || 0_i64
      next_n = n + 1
      ctx.store["n"] = next_n
      ctx.result = {"n" => next_n} of String => Alumna::AnyData
      nil
    end
    session = Alumna::Http::WebSocketSession.new(
      HTTP::WebSocket.new(IO::Memory.new),
      HTTP::Headers.new,
      "127.0.0.1",
      app,
    )
    first = session.process_frame(%({"id":"1","method":"find","path":"/items"}))
    second = session.process_frame(%({"id":"2","method":"find","path":"/items"}))
    first["result"].as(Hash)["n"].should eq(1)
    second["result"].as(Hash)["n"].should eq(2)
    session.store["n"].should eq(2)
  end

  it "registers the session and unregisters on unregister" do
    app = Alumna::App.new
    session = Alumna::Http::WebSocketSession.new(
      HTTP::WebSocket.new(IO::Memory.new),
      HTTP::Headers.new,
      "127.0.0.1",
      app,
    )
    session.store["connection_id"].should eq(session.id)
    app.connections.send(session.id, "ping").should be_true
    session.unregister
    app.connections.send(session.id, "ping").should be_false
  end

  it "wraps HTTP::WebSocket send and close" do
    ws = HTTP::WebSocket.new(IO::Memory.new)
    wrap = Alumna::Http::WebSocketSocket.new(ws)
    wrap.send("hi")
    wrap.send("hi".to_slice)
    wrap.close
    wrap.send("after-close")
    wrap.close
  end

  it "keeps a session started on the first frame" do
    sessions = Alumna::Session.new(Alumna::MemorySessionStore.new(ttl: 1.hour), required: false)
    app = Alumna::App.new
    app.before sessions.rule
    app.use("/items", Alumna.memory)
    app.services["/items"].before(on: :create) do |ctx|
      sessions.start(ctx, Alumna.hash(user_id: "u1"))
      nil
    end
    app.services["/items"].before(on: :find) do |ctx|
      sess = ctx.store["session"]?.as?(Hash(String, Alumna::AnyData))
      ctx.result = sess || ({} of String => Alumna::AnyData)
      nil
    end
    session = Alumna::Http::WebSocketSession.new(
      HTTP::WebSocket.new(IO::Memory.new),
      HTTP::Headers.new,
      "127.0.0.1",
      app,
    )
    session.process_frame(%({"id":"1","method":"create","path":"/items","data":{}}))
    found = session.process_frame(%({"id":"2","method":"find","path":"/items"}))
    found["result"].as(Hash)["user_id"].should eq("u1")
  end

  it "keeps JWT claims in the socket store" do
    secret = "s3cret-key-for-tests"
    token = Alumna::JWT.encode(Alumna.hash(sub: "u1", exp: Time.utc.to_unix + 60), secret)
    app = Alumna::App.new
    app.before Alumna.jwt(secret)
    app.use("/me", Alumna.memory)
    app.services["/me"].before do |ctx|
      claims = ctx.store["jwt"]?.as?(Hash(String, Alumna::AnyData))
      next Alumna::ServiceError.unauthorized unless claims
      ctx.result = claims
      nil
    end
    session = Alumna::Http::WebSocketSession.new(
      HTTP::WebSocket.new(IO::Memory.new),
      HTTP::Headers{"Authorization" => "Bearer #{token}"},
      "127.0.0.1",
      app,
    )
    first = session.process_frame(%({"id":"1","method":"find","path":"/me"}))
    second = session.process_frame(%({"id":"2","method":"find","path":"/me"}))
    first["result"].as(Hash)["sub"].should eq("u1")
    second["result"].as(Hash)["sub"].should eq("u1")
    session.store.has_key?("jwt").should be_true
  end
end

describe "WebSocket handshake" do
  app = Alumna::App.new
  app.use("/items", Alumna.memory)
  client = Alumna::Testing::AppClient.new(app)

  it "keeps REST find on the same server" do
    res = client.get("/items")
    res.status.should eq(200)
  end

  it "rejects an upgrade without a version" do
    res = client.get("/", headers: {
      "Upgrade"    => "websocket",
      "Connection" => "Upgrade",
    })
    res.status.should eq(426)
    res.headers["Sec-WebSocket-Version"].should eq("13")
    res.json_hash["error"].should eq("WebSocket version is not supported")
  end

  it "rejects an upgrade with a wrong version" do
    res = client.get("/", headers: {
      "Upgrade"               => "websocket",
      "Connection"            => "Upgrade",
      "Sec-WebSocket-Version" => "12",
    })
    res.status.should eq(426)
    res.json_hash["error"].should eq("WebSocket version is not supported")
  end

  it "rejects an upgrade without a key" do
    res = client.get("/", headers: {
      "Upgrade"               => "websocket",
      "Connection"            => "Upgrade",
      "Sec-WebSocket-Version" => "13",
    })
    res.status.should eq(400)
    res.json_hash["error"].should eq("WebSocket key is missing")
  end

  it "rejects an upgrade with an empty key" do
    res = client.get("/", headers: {
      "Upgrade"               => "websocket",
      "Connection"            => "Upgrade",
      "Sec-WebSocket-Version" => "13",
      "Sec-WebSocket-Key"     => "",
    })
    res.status.should eq(400)
    res.json_hash["error"].should eq("WebSocket key is missing")
  end

  it "rejects a non-GET upgrade" do
    res = client.post("/", nil, headers: {
      "Upgrade"               => "websocket",
      "Connection"            => "Upgrade",
      "Sec-WebSocket-Version" => "13",
      "Sec-WebSocket-Key"     => RFC_KEY,
    })
    res.status.should eq(400)
    res.json_hash["error"].should eq("WebSocket upgrade must use GET")
  end

  it "completes a valid handshake with 101" do
    res = client.get("/", headers: {
      "Upgrade"               => "websocket",
      "Connection"            => "Upgrade",
      "Sec-WebSocket-Version" => "13",
      "Sec-WebSocket-Key"     => RFC_KEY,
    })
    res.status.should eq(101)
    res.headers["Upgrade"].should eq("websocket")
    res.headers["Connection"].should eq("Upgrade")
    res.headers["Sec-WebSocket-Accept"].should eq(RFC_ACCEPT)
  end
end

describe "WebSocket handshake over TCP" do
  it "accepts HTTP::WebSocket.new and does not run REST" do
    app = Alumna::App.new
    app.use("/items", Alumna.memory)
    router = Alumna::Http::Router.new(app)
    server = HTTP::Server.new { |ctx| router.handle(ctx) }
    port = 34610
    server.bind_tcp("127.0.0.1", port)
    spawn { server.listen }
    wait_for_port("127.0.0.1", port)

    ws = HTTP::WebSocket.new("127.0.0.1", "/", port)
    ws.close
    server.close
  end

  it "creates and finds over a live socket" do
    app = Alumna::App.new
    app.use("/items", Alumna.memory)
    router = Alumna::Http::Router.new(app)
    server = HTTP::Server.new { |ctx| router.handle(ctx) }
    port = 34622
    server.bind_tcp("127.0.0.1", port)
    spawn { server.listen }
    wait_for_port("127.0.0.1", port)

    ws = HTTP::WebSocket.new("127.0.0.1", "/", port)
    ws.send(%({"id":"live","method":"create","path":"/items","data":{"name":"z"}}))
    msg = ws.receive
    msg.should be_a(String)
    body = Alumna::JsonHelper.from_string(msg.as(String)).as(Hash)
    body["id"].should eq("live")
    body["result"].as(Hash)["name"].should eq("z")
    ws.close
    server.close
  end

  it "sends from one live socket table to another socket" do
    app = Alumna::App.new
    app.use("/items", Alumna.memory)
    app.services["/items"].before(on: :find) do |ctx|
      id = ctx.store["connection_id"]?.as?(String)
      ctx.result = {"connection_id" => id} of String => Alumna::AnyData
      nil
    end
    router = Alumna::Http::Router.new(app)
    server = HTTP::Server.new { |ctx| router.handle(ctx) }
    port = 34630
    server.bind_tcp("127.0.0.1", port)
    spawn { server.listen }
    wait_for_port("127.0.0.1", port)

    a = HTTP::WebSocket.new("127.0.0.1", "/", port)
    b = HTTP::WebSocket.new("127.0.0.1", "/", port)
    a.send(%({"id":"a","method":"find","path":"/items"}))
    b.send(%({"id":"b","method":"find","path":"/items"}))
    a_body = Alumna::JsonHelper.from_string(a.receive.as(String)).as(Hash)
    b_body = Alumna::JsonHelper.from_string(b.receive.as(String)).as(Hash)
    b_id = b_body["result"].as(Hash)["connection_id"].as(String)
    app.connections.send(b_id, "from-a").should be_true
    b.receive.should eq("from-a")
    a.close
    b.close
    server.close
  end

  it "send_topic reaches two live sockets on one topic" do
    app = Alumna::App.new
    app.use("/items", Alumna.memory)
    app.services["/items"].before(on: :find) do |ctx|
      id = ctx.store["connection_id"]?.as?(String)
      ctx.result = {"connection_id" => id} of String => Alumna::AnyData
      nil
    end
    router = Alumna::Http::Router.new(app)
    server = HTTP::Server.new { |ctx| router.handle(ctx) }
    port = 34631
    server.bind_tcp("127.0.0.1", port)
    spawn { server.listen }
    wait_for_port("127.0.0.1", port)

    a = HTTP::WebSocket.new("127.0.0.1", "/", port)
    b = HTTP::WebSocket.new("127.0.0.1", "/", port)
    a.send(%({"id":"a","method":"find","path":"/items"}))
    b.send(%({"id":"b","method":"find","path":"/items"}))
    a_id = Alumna::JsonHelper.from_string(a.receive.as(String)).as(Hash)["result"].as(Hash)["connection_id"].as(String)
    b_id = Alumna::JsonHelper.from_string(b.receive.as(String)).as(Hash)["result"].as(Hash)["connection_id"].as(String)
    app.connections.watch(a_id, "posts")
    app.connections.watch(b_id, "posts")
    app.connections.send_topic("posts", "fanout")
    a.receive.should eq("fanout")
    b.receive.should eq("fanout")
    a.close
    b.close
    server.close
  end
end
