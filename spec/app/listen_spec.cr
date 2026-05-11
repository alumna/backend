require "../spec_helper"
require "http/client"

describe "App#listen" do
  it "boots the server, binds to the port, and handles requests over TCP" do
    app = Alumna::App.new
    app.use("/listen-test", Alumna::MemoryAdapter.new)

    # Use a high port to avoid conflicts
    port = 34567

    # We bind to 0.0.0.0 specifically to trigger the STDERR warning
    # internally, ensuring 100% coverage of the App#listen method.
    spawn do
      app.listen(port, host: "0.0.0.0")
    end

    # Yield the fiber to let the server boot
    sleep 0.1.seconds

    # Make one real TCP HTTP request to prove the listener works
    res = HTTP::Client.get("http://127.0.0.1:#{port}/listen-test")
    res.status_code.should eq(200)
  end
end
