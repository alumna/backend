require "http/web_socket"
require "http/headers"

module Alumna
  module Testing
    # In-process WebSocket session. No listen. Same dispatch as a live socket.
    class SocketClient
      getter session : Http::WebSocketSession
      getter app : App

      def initialize(@app : App, headers : HTTP::Headers = HTTP::Headers.new)
        @session = Http::WebSocketSession.new(
          HTTP::WebSocket.new(IO::Memory.new),
          headers,
          "127.0.0.1",
          @app,
        )
      end

      def connection_id : String
        @session.id
      end

      def send(text : String) : Hash(String, AnyData)
        @session.process_frame(text)
      end

      def call(
        method : String,
        path : String,
        *,
        id : String = "1",
        resource_id : String? = nil,
        data : Hash(String, AnyData)? = nil,
        params : Hash(String, AnyData)? = nil,
      ) : Hash(String, AnyData)
        frame = {} of String => AnyData
        frame["id"] = id
        frame["method"] = method
        frame["path"] = path
        frame["resource_id"] = resource_id if resource_id
        frame["data"] = data if data
        frame["params"] = params if params
        send(JsonHelper.to_string(frame))
      end

      def close : Nil
        @session.unregister
        @session.socket.close
      end
    end
  end
end
