require "../spec_helper"
require "http/client"

private def wait_for_port(host : String, port : Int32, timeout : Time::Span = 5.seconds)
  deadline = Time.instant + timeout
  loop do
    begin
      TCPSocket.new(host, port).close
      return # connection succeeded - server is up
    rescue
      raise "Server did not start within #{timeout}" if Time.instant > deadline
      Fiber.yield
    end
  end
end

describe "App#listen" do
  it "boots the server, binds to the port, and handles requests over TCP" do
    app = Alumna::App.new
    app.use("/listen-test", Alumna::MemoryAdapter.new)

    # Use a high port to avoid conflicts
    port = 34567

    # We bind to 0.0.0.0 specifically to trigger the STDERR warning
    # internally, ensuring 100% coverage of the App#listen method.
    spawn do
      app.listen(port, host: "0.0.0.0", trap_signals: false)
    end

    # Wait the server boot
    wait_for_port("127.0.0.1", port)

    # Make one real TCP HTTP request to prove the listener works
    res = HTTP::Client.get("http://127.0.0.1:#{port}/listen-test")
    res.status_code.should eq(200)

    app.close
  end
end

describe "App#close and graceful shutdown" do
  it "waits for active requests to finish before returning from listen" do
    app = Alumna::App.new
    request_started = Channel(Nil).new # ← synchronization point

    app.use "/slow", Alumna.memory(Alumna::Schema.new) {
      before do |ctx|
        request_started.send(nil) # ← fires after @active_requests.add(1)
        sleep 0.5.seconds
        ctx.result = {"ok" => true} of String => Alumna::AnyData
        nil
      end
    }

    port = 34568
    listen_done = Channel(Nil).new
    spawn do
      app.listen(port, host: "127.0.0.1", shutdown_timeout: 2.seconds, trap_signals: false)
      listen_done.send(nil)
    end

    wait_for_port("127.0.0.1", port)

    req_done = Channel(Int32).new
    spawn do
      res = HTTP::Client.get("http://127.0.0.1:#{port}/slow")
      req_done.send(res.status_code)
    end

    request_started.receive # ← blocks until @active_requests is already 1

    app.close

    select
    when status = req_done.receive
      status.should eq(200)
    when listen_done.receive
      fail "listen returned before the active request finished"
    end

    listen_done.receive
  end
end
