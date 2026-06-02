require "../spec_helper"
require "http/client"
require "socket"

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
    request_started = Channel(Nil).new

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

    # We use a union type in case a forceful shutdown causes an IO::Error
    req_done = Channel(Int32 | Exception).new
    spawn do
      begin
        res = HTTP::Client.get("http://127.0.0.1:#{port}/slow")
        req_done.send(res.status_code)
      rescue ex
        req_done.send(ex)
      end
    end

    # Blocks until @active_requests is guaranteed to be 1
    request_started.receive

    # Trigger shutdown while the request is actively sleeping
    app.close

    # Proof 1: Graceful shutdown worked because the request completed normally.
    # If app.close killed the socket, this would be an Exception (e.g. IO::Error).
    result = req_done.receive
    result.should eq(200)

    # Proof 2: The listen loop unblocked and gracefully exited.
    listen_done.receive
  end

  describe "App signals and graceful shutdown" do
    it "traps SIGINT to trigger shutdown" do
      app = Alumna::App.new
      port = 34569
      listen_done = Channel(Nil).new

      spawn do
        # trap_signals is true by default, but we pass it explicitly for clarity
        app.listen(port, host: "127.0.0.1", trap_signals: true)
        listen_done.send(nil)
      end

      # Wait for the server to be fully booted. This guarantees that
      # Signal::INT.trap has already been successfully registered.
      wait_for_port("127.0.0.1", port)

      # Send SIGINT (Ctrl+C) to the current process (the spec runner).
      # Because we trapped it, this will safely invoke our `trap_handler`,
      # print the shutdown message, and call `app.close` without killing the test suite!
      Process.signal(Signal::INT, Process.pid)

      # The listener should unblock and finish gracefully
      listen_done.receive
    end

    it "traps SIGTERM to trigger shutdown" do
      app = Alumna::App.new
      port = 34570
      listen_done = Channel(Nil).new

      spawn do
        app.listen(port, host: "127.0.0.1", trap_signals: true)
        listen_done.send(nil)
      end

      wait_for_port("127.0.0.1", port)

      # Send SIGTERM. This ensures the second block in `src/app.cr` is covered.
      Process.signal(Signal::TERM, Process.pid)

      # The listener should unblock and finish gracefully
      listen_done.receive
    end

    it "exits and prints a warning if the shutdown timeout is reached" do
      app = Alumna::App.new
      request_started = Channel(Nil).new
      request_finished = Channel(Nil).new

      # A route that takes 0.5 seconds to process
      app.use "/timeout", Alumna.memory(Alumna::Schema.new) {
        before do |ctx|
          request_started.send(nil)
          sleep 0.1.seconds
          request_finished.send(nil)

          ctx.result = {"ok" => true} of String => Alumna::AnyData
          nil
        end
      }

      port = 34571
      listen_done = Channel(Nil).new
      spawn do
        # Configure a very short timeout: 0.1 seconds
        app.listen(port, host: "127.0.0.1", shutdown_timeout: 0.01.seconds, trap_signals: false)
        listen_done.send(nil)
      end

      wait_for_port("127.0.0.1", port)

      spawn do
        begin
          HTTP::Client.get("http://127.0.0.1:#{port}/timeout")
        rescue
          # We don't care about the client result here, just that it triggered the route
        end
      end

      # 1. Wait until the request is inside the `before` block (counter is now 1)
      request_started.receive

      # 2. Trigger shutdown. The server will wait, but ONLY for 0.1 seconds.
      app.close

      # 3. This will unblock after ~0.1 seconds because the timeout is reached.
      # It will hit the branch: puts "Shutdown timeout reached. Exiting with #{rem} active requests."
      listen_done.receive

      # 4. Clean up: wait for the sleeping request to finish so we don't leak
      # background fibers into other tests.
      request_finished.receive
    end
  end

  describe "App#listen with Unix Socket" do
    it "binds to a unix socket and sets ctx.provider to local" do
      app = Alumna::App.new
      app.use "/provider", Alumna.memory(Alumna::Schema.new) {
        before do |ctx|
          ctx.result = {"provider" => ctx.provider} of String => Alumna::AnyData
          nil
        end
      }

      port = 34572
      unix_path = "/tmp/alumna_test_#{Random::Secure.hex(4)}.sock"

      spawn do
        app.listen(port, host: "127.0.0.1", unix_socket: unix_path, trap_signals: false)
      end

      wait_for_port("127.0.0.1", port)

      begin
        # 1. Test TCP -> "rest"
        res_tcp = HTTP::Client.get("http://127.0.0.1:#{port}/provider")
        res_tcp.status_code.should eq(200)
        JSON.parse(res_tcp.body)["provider"].as_s.should eq("rest")

        # 2. Test Unix -> "local"
        socket = UNIXSocket.new(unix_path)
        socket << "GET /provider HTTP/1.1\r\nHost: localhost\r\n\r\n"
        res_unix = HTTP::Client::Response.from_io(socket)
        res_unix.status_code.should eq(200)
        JSON.parse(res_unix.body)["provider"].as_s.should eq("local")
        socket.close
      ensure
        app.close
        File.delete?(unix_path)
      end
    end

    it "binds solely to a unix socket when port is nil" do
      app = Alumna::App.new
      app.use "/only-unix", Alumna::MemoryAdapter.new(Alumna::Schema.new)

      unix_path = "/tmp/alumna_test_only_#{Random::Secure.hex(4)}.sock"
      listen_done = Channel(Nil).new

      spawn do
        app.listen(port: nil, unix_socket: unix_path, trap_signals: false)
        listen_done.send(nil)
      end

      deadline = Time.instant + 5.seconds
      while !File.exists?(unix_path)
        raise "Socket not created" if Time.instant > deadline
        sleep 0.05.seconds
      end

      begin
        socket = UNIXSocket.new(unix_path)
        socket << "GET /only-unix HTTP/1.1\r\nHost: localhost\r\n\r\n"
        res_unix = HTTP::Client::Response.from_io(socket)
        res_unix.status_code.should eq(200)
        socket.close
      ensure
        app.close
        listen_done.receive
        File.delete?(unix_path)
      end
    end
  end
end
