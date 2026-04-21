require "http/server"

module Alumna
  class App
    getter serializer : Http::Serializer
    getter services : Hash(String, Service)

    # Defaults
    property max_body_size : Int64 = 1_048_576 # 1 MB default

    def initialize(@serializer : Http::Serializer = Http::JsonSerializer.new)
      @services = {} of String => Service
    end

    def use(path : String, service : Service) : self
      @services[path] = service
      self
    end

    def listen(port : Int32 = 3000)
      router = Http::Router.new(self)
      server = HTTP::Server.new { |ctx| router.handle(ctx) }
      puts "Listening on http://0.0.0.0:#{port}"
      server.listen("0.0.0.0", port)
    end
  end
end
