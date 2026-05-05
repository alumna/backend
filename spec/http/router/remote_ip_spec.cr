require "../../spec_helper"
require "http/client"
require "http/server"

# A tiny service that just echoes back the ip the router computed
class IpEchoService < Alumna::MemoryAdapter
  def initialize
    super(Alumna::Schema.new)
  end

  def find(ctx) : Array(Hash(String, Alumna::AnyData))
    [{"ip" => ctx.remote_ip} of String => Alumna::AnyData]
  end
end

private def with_router(trusted, &)
  app = Alumna::App.new
  app.use("/ip", IpEchoService.new)
  router = Alumna::Http::Router.new(app, trusted)
  server = HTTP::Server.new { |ctx| router.handle(ctx) }
  port = 4000 + rand(1000)
  server.bind_tcp("127.0.0.1", port)
  spawn { server.listen }
  Fiber.yield
  yield port
ensure
  server.try &.close
end

private def get_ip(port, headers = HTTP::Headers.new)
  resp = HTTP::Client.get("http://127.0.0.1:#{port}/ip", headers: headers)
  JSON.parse(resp.body)[0]["ip"].as_s
end

describe "Router remote_ip with trusted proxies" do
  it "uses direct ip when TrustMode::None (covers default)" do
    with_router(nil) do |port|
      ip = get_ip(port)
      ip.should eq "127.0.0.1"
    end
  end

  it "initializes TrustMode::All (line 22)" do
    with_router(true) do |port|
      headers = HTTP::Headers{
        "X-Forwarded-For" => "1.2.3.4, 5.6.7.8",
      }
      ip = get_ip(port, headers)
      # trust_all → returns first address in XFF
      ip.should eq "1.2.3.4"
    end
  end

  it "initializes TrustMode::List (line 23)" do
    with_router(["127.0.0.1"]) do |port|
      headers = HTTP::Headers{
        "X-Forwarded-For" => "9.9.9.9, 8.8.8.8",
      }
      ip = get_ip(port, headers)
      # remote (127.0.0.1) is trusted, so we walk XFF right-to-left
      # skipping trusted proxies, returns 8.8.8.8
      ip.should eq "8.8.8.8"
    end
  end

  it "parses Forwarded header (covers parse_forwarded)" do
    with_router(true) do |port|
      headers = HTTP::Headers{
        "Forwarded" => "for=\"[2001:db8::1]\";proto=https, for=2.2.2.2",
      }
      ip = get_ip(port, headers)
      ip.should eq "2001:db8::1"
    end
  end

  it "falls back to X-Real-IP (covers parse_x_real_ip)" do
    with_router(true) do |port|
      headers = HTTP::Headers{"X-Real-IP" => "3.3.3.3"}
      ip = get_ip(port, headers)
      ip.should eq "3.3.3.3"
    end
  end

  it "returns remote when no proxy headers and not trusted" do
    with_router(["10.0.0.1"]) do |port| # 127.0.0.1 NOT trusted
      ip = get_ip(port)
      ip.should eq "127.0.0.1"
    end
  end
end
