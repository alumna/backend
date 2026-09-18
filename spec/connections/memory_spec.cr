require "../spec_helper"

class FakePushSocket < Alumna::PushSocket
  getter messages = [] of String | Bytes
  getter? closed = false

  def send(payload : String | Bytes) : Nil
    @messages << payload
  end

  def close : Nil
    @closed = true
  end
end

class BoomPushSocket < Alumna::PushSocket
  def send(payload : String | Bytes) : Nil
    raise IO::Error.new("closed")
  end

  def close : Nil
  end
end

class BoomCloseSocket < Alumna::PushSocket
  def send(payload : String | Bytes) : Nil
  end

  def close : Nil
    raise IO::Error.new("closed")
  end
end

describe Alumna::MemoryConnections do
  it "sends to one registered id" do
    hub = Alumna::MemoryConnections.new
    a = FakePushSocket.new
    b = FakePushSocket.new
    hub.register("a", a)
    hub.register("b", b)
    hub.send("b", "hello").should be_true
    b.messages.should eq(["hello"])
    a.messages.should be_empty
  end

  it "sends bytes" do
    hub = Alumna::MemoryConnections.new
    sock = FakePushSocket.new
    hub.register("s", sock)
    hub.send("s", "hi".to_slice).should be_true
    sock.messages[0].should eq("hi".to_slice)
  end

  it "returns false for an unknown id" do
    Alumna::MemoryConnections.new.send("missing", "x").should be_false
  end

  it "stops sending after unregister" do
    hub = Alumna::MemoryConnections.new
    sock = FakePushSocket.new
    hub.register("s", sock)
    hub.unregister("s")
    hub.send("s", "x").should be_false
    sock.messages.should be_empty
  end

  it "replaces a socket with the same id" do
    hub = Alumna::MemoryConnections.new
    first = FakePushSocket.new
    second = FakePushSocket.new
    hub.register("s", first)
    hub.register("s", second)
    hub.send("s", "x").should be_true
    first.messages.should be_empty
    second.messages.should eq(["x"])
  end

  it "returns false when send raises IO::Error" do
    hub = Alumna::MemoryConnections.new
    hub.register("s", BoomPushSocket.new)
    hub.send("s", "x").should be_false
  end

  it "rejects an empty id" do
    expect_raises(ArgumentError, "connection id must not be empty") do
      Alumna::MemoryConnections.new.register("", FakePushSocket.new)
    end
  end

  it "close on a fake socket" do
    sock = FakePushSocket.new
    sock.close
    sock.closed?.should be_true
  end

  it "send_topic delivers to every watcher of the topic" do
    hub = Alumna::MemoryConnections.new
    a = FakePushSocket.new
    b = FakePushSocket.new
    c = FakePushSocket.new
    hub.register("a", a)
    hub.register("b", b)
    hub.register("c", c)
    hub.watch("a", "posts")
    hub.watch("b", "posts")
    hub.watch("c", "other")
    hub.send_topic("posts", "hello")
    a.messages.should eq(["hello"])
    b.messages.should eq(["hello"])
    c.messages.should be_empty
  end

  it "send_topic can send bytes" do
    hub = Alumna::MemoryConnections.new
    sock = FakePushSocket.new
    hub.register("s", sock)
    hub.watch("s", "posts")
    hub.send_topic("posts", "hi".to_slice)
    sock.messages[0].should eq("hi".to_slice)
  end

  it "unwatch stops delivery" do
    hub = Alumna::MemoryConnections.new
    sock = FakePushSocket.new
    hub.register("s", sock)
    hub.watch("s", "posts")
    hub.unwatch("s", "posts")
    hub.send_topic("posts", "x")
    sock.messages.should be_empty
  end

  it "unregister clears watches" do
    hub = Alumna::MemoryConnections.new
    sock = FakePushSocket.new
    hub.register("s", sock)
    hub.watch("s", "posts")
    hub.unregister("s")
    hub.register("s", sock)
    hub.send_topic("posts", "x")
    sock.messages.should be_empty
  end

  it "send_topic on an unknown topic is a no-op" do
    Alumna::MemoryConnections.new.send_topic("none", "x")
  end

  it "unwatch of an unknown pair is a no-op" do
    hub = Alumna::MemoryConnections.new
    hub.unwatch("s", "posts")
  end

  it "watch twice on the same topic still sends once" do
    hub = Alumna::MemoryConnections.new
    sock = FakePushSocket.new
    hub.register("s", sock)
    hub.watch("s", "posts")
    hub.watch("s", "posts")
    hub.send_topic("posts", "x")
    sock.messages.should eq(["x"])
  end

  it "skips a watcher with no registered socket" do
    hub = Alumna::MemoryConnections.new
    sock = FakePushSocket.new
    hub.watch("s", "posts")
    hub.send_topic("posts", "x")
    sock.messages.should be_empty
    hub.register("s", sock)
    hub.send_topic("posts", "y")
    sock.messages.should eq(["y"])
  end

  it "send_topic continues after IO::Error" do
    hub = Alumna::MemoryConnections.new
    boom = BoomPushSocket.new
    ok = FakePushSocket.new
    hub.register("boom", boom)
    hub.register("ok", ok)
    hub.watch("boom", "posts")
    hub.watch("ok", "posts")
    hub.send_topic("posts", "x")
    ok.messages.should eq(["x"])
  end

  it "rejects an empty topic" do
    expect_raises(ArgumentError, "topic must not be empty") do
      Alumna::MemoryConnections.new.watch("s", "")
    end
  end

  it "rejects an empty id on watch" do
    expect_raises(ArgumentError, "connection id must not be empty") do
      Alumna::MemoryConnections.new.watch("", "posts")
    end
  end

  it "close_all closes sockets and clears the table" do
    hub = Alumna::MemoryConnections.new
    sock = FakePushSocket.new
    hub.register("s", sock)
    hub.watch("s", "posts")
    hub.close_all
    sock.closed?.should be_true
    hub.send("s", "x").should be_false
    hub.send_topic("posts", "x")
    sock.messages.should be_empty
  end

  it "close_all continues after IO::Error" do
    hub = Alumna::MemoryConnections.new
    hub.register("boom", BoomCloseSocket.new)
    hub.register("ok", FakePushSocket.new)
    hub.close_all
  end

  it "unwatch one topic leaves the other" do
    hub = Alumna::MemoryConnections.new
    sock = FakePushSocket.new
    hub.register("s", sock)
    hub.watch("s", "posts")
    hub.watch("s", "other")
    hub.unwatch("s", "posts")
    hub.send_topic("posts", "no")
    hub.send_topic("other", "yes")
    sock.messages.should eq(["yes"])
  end
end
