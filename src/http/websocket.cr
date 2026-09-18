require "http/web_socket"
require "uuid"
require "./serializer"
require "./responder"

module Alumna
  module Http
    # ctx.provider for every WebSocket session. Not "rest" or "local".
    WEBSOCKET_PROVIDER = "websocket"

    # RFC 6455: Upgrade: websocket and Connection contains Upgrade.
    def self.websocket_upgrade?(request : HTTP::Request) : Bool
      return false unless upgrade = request.headers["Upgrade"]?
      return false unless upgrade.compare("websocket", case_insensitive: true) == 0
      request.headers.includes_word?("Connection", "Upgrade")
    end

    # Same path match as REST. /items and /items/ are identical.
    def self.resolve_mounted_service(services : Hash(String, Service), path : String) : {Service, String?}?
      path = path == "/" ? path : path.chomp('/')

      if service = services[path]?
        return {service, nil}
      end

      sep = path.index('/', 1)
      return nil unless sep
      return nil if path.index('/', sep + 1)

      base = path[0...sep]
      service = services[base]?
      return nil unless service

      id = path[sep + 1..]
      return nil if id.empty?
      {service, id}
    end

    # Handshake or an error response. On success, HTTP::Server runs the
    # upgrade IO after this method returns. Do not parse a REST body.
    def self.accept_websocket(
      http_ctx : HTTP::Server::Context,
      app : App,
      remote_ip : String,
    ) : Nil
      request = http_ctx.request
      response = http_ctx.response
      serializer = app.serializer

      unless request.method == "GET"
        write_upgrade_error(response, serializer, ServiceError.bad_request("WebSocket upgrade must use GET"))
        return
      end

      version = request.headers["Sec-WebSocket-Version"]?
      unless version == ::HTTP::WebSocket::Protocol::VERSION
        response.headers["Sec-WebSocket-Version"] = ::HTTP::WebSocket::Protocol::VERSION
        write_upgrade_error(response, serializer, ServiceError.new("WebSocket version is not supported", 426))
        return
      end

      key = request.headers["Sec-WebSocket-Key"]?
      if key.nil? || key.empty?
        write_upgrade_error(response, serializer, ServiceError.bad_request("WebSocket key is missing"))
        return
      end

      response.status = :switching_protocols
      response.headers["Upgrade"] = "websocket"
      response.headers["Connection"] = "Upgrade"
      response.headers["Sec-WebSocket-Accept"] = ::HTTP::WebSocket::Protocol.key_challenge(key)
      response.upgrade do |io|
        socket = ::HTTP::WebSocket.new(io, sync_close: false)
        session = WebSocketSession.new(socket, request.headers.dup, remote_ip, app)
        socket.on_message { |text| session.handle_text(text) }
        socket.on_binary { |bytes| session.handle_binary(bytes) }
        socket.on_close { session.unregister }
        begin
          session.socket.run
        ensure
          session.unregister
        end
      end
    end

    private def self.write_upgrade_error(
      response : HTTP::Server::Response,
      serializer : Serializer,
      error : ServiceError,
    ) : Nil
      response.content_type = serializer.content_type
      Responder.write_error(response, error, serializer)
    end

    # HTTP::WebSocket as Alumna::Socket. send/close never raise into Connections.
    class WebSocketSocket < PushSocket
      def initialize(@ws : ::HTTP::WebSocket)
      end

      def send(payload : String | Bytes) : Nil
        @ws.send(payload)
      rescue IO::Error
      end

      def close : Nil
        @ws.close
      rescue IO::Error
      end
    end

    # One upgraded socket. provider is always WEBSOCKET_PROVIDER.
    # Handshake headers are copied onto every frame context.
    # One store Hash for the life of the socket (ROADMAP 4.2).
    class WebSocketSession
      getter socket : ::HTTP::WebSocket
      getter provider : String
      getter headers : HTTP::Headers
      getter remote_ip : String
      getter app : App
      getter store : Hash(String, StoreType)
      getter id : String

      def initialize(@socket : ::HTTP::WebSocket, @headers : HTTP::Headers, @remote_ip : String, @app : App)
        @provider = WEBSOCKET_PROVIDER
        @id = UUID.random.to_s
        @store = {} of String => StoreType
        @store["connection_id"] = @id
        @app.connections.register(@id, WebSocketSocket.new(@socket))
      end

      def unregister : Nil
        @app.connections.unregister(@id)
      end

      # One text frame → dispatch → one JSON reply. Never raise to the socket loop.
      def handle_text(text : String) : Nil
        reply = process_frame(text)
        send_json(reply)
      rescue ex : Exception
        send_json(error_payload(nil, ServiceError.internal(ex.message || "Unexpected error")))
      end

      # JSON frames are text. Binary is an error reply, not a raise.
      def handle_binary(bytes : Bytes) : Nil
        if oversize?(bytes.size)
          send_json(error_payload(nil, ServiceError.new("Payload Too Large", 413)))
          return
        end
        send_json(error_payload(nil, ServiceError.bad_request("WebSocket JSON text frames only")))
      end

      # Parse one frame and run App#dispatch. Used by specs without a live socket.
      def process_frame(text : String) : Hash(String, AnyData)
        if oversize?(text.bytesize)
          return error_payload(nil, ServiceError.new("Payload Too Large", 413))
        end
        parsed = JsonHelper.from_string(text)
        unless parsed.is_a?(Hash(String, AnyData))
          return error_payload(nil, ServiceError.bad_request("Frame must be a JSON object"))
        end

        frame_id = parsed["id"]?
        method_raw = parsed["method"]?
        unless method_raw.is_a?(String)
          return error_payload(frame_id, ServiceError.bad_request("method is missing"))
        end

        method = frame_method?(method_raw)
        unless method
          return error_payload(frame_id, ServiceError.new("Method not allowed", 405))
        end

        path_raw = parsed["path"]?
        unless path_raw.is_a?(String)
          return error_payload(frame_id, ServiceError.bad_request("path is missing"))
        end

        resource_id = frame_id_string(parsed["resource_id"]?)
        match = Http.resolve_mounted_service(@app.services, path_raw)
        unless match
          return error_payload(frame_id, ServiceError.not_found("No service at #{path_raw}"))
        end

        service, path_id = match
        id = resource_id || path_id

        data_raw = parsed["data"]?
        data = case data_raw
               when Nil
                 {} of String => AnyData
               when Hash(String, AnyData)
                 data_raw
               else
                 return error_payload(frame_id, ServiceError.bad_request("data must be an object"))
               end

        params_view = params_from_frame(parsed["params"]?)
        unless params_view
          return error_payload(frame_id, ServiceError.bad_request("params must be an object"))
        end

        ctx = RuleContext.new(
          app: @app,
          service: service,
          path: service.path,
          method: method,
          phase: RulePhase::Before,
          http_method: http_verb(method),
          remote_ip: @remote_ip,
          provider: @provider,
          params: params_view,
          headers: HeadersView.new(@headers),
          id: id,
          data: data,
          store: @store,
        )
        @app.dispatch(service, ctx)

        if err = ctx.error
          error_payload(frame_id, err)
        else
          success_payload(frame_id, ctx.result)
        end
      rescue ex : JSON::ParseException
        error_payload(nil, ServiceError.bad_request("Invalid JSON"))
      end

      private def frame_method?(name : String) : ServiceMethod?
        case name
        when "find"   then ServiceMethod::Find
        when "get"    then ServiceMethod::Get
        when "create" then ServiceMethod::Create
        when "update" then ServiceMethod::Update
        when "patch"  then ServiceMethod::Patch
        when "remove" then ServiceMethod::Remove
        else
          nil
        end
      end

      private def http_verb(method : ServiceMethod) : String
        case method
        when .create? then "POST"
        when .update? then "PUT"
        when .patch?  then "PATCH"
        when .remove? then "DELETE"
        else
          "GET"
        end
      end

      private def frame_id_string(value : AnyData) : String?
        case value
        when Nil    then nil
        when String then value.empty? ? nil : value
        when Int64  then value.to_s
        else
          nil
        end
      end

      private def params_from_frame(raw : AnyData) : ParamsView?
        http_params = HTTP::Params.new
        case raw
        when Nil
          ParamsView.new(http_params)
        when Hash(String, AnyData)
          raw.each do |key, value|
            add_param(http_params, key, value)
          end
          ParamsView.new(http_params)
        else
          nil
        end
      end

      private def add_param(http_params : HTTP::Params, key : String, value : AnyData) : Nil
        case value
        when Array
          value.each { |item| http_params.add(key, param_string(item)) }
        else
          http_params.add(key, param_string(value))
        end
      end

      private def param_string(value : AnyData) : String
        case value
        when String then value
        when Nil    then ""
        when Bool, Int64, Float64
          value.to_s
        else
          JsonHelper.to_string(value)
        end
      end

      private def success_payload(frame_id : AnyData, result : ServiceResult) : Hash(String, AnyData)
        payload = {} of String => AnyData
        payload["id"] = frame_id unless frame_id.nil?
        payload["result"] = result_as_any(result)
        payload
      end

      # Array(Hash) is ServiceResult but not Array(AnyData). Copy into AnyData.
      private def result_as_any(result : ServiceResult) : AnyData
        case result
        in Hash(String, AnyData)
          result
        in Array(Hash(String, AnyData))
          any = Array(AnyData).new(result.size)
          result.each { |row| any << row }
          any
        in Nil
          nil
        end
      end

      private def error_payload(frame_id : AnyData, error : ServiceError) : Hash(String, AnyData)
        err = {} of String => AnyData
        err["message"] = error.message
        err["status"] = error.status.to_i64
        if details = error.details?
          err["details"] = details
        end
        payload = {} of String => AnyData
        payload["id"] = frame_id unless frame_id.nil?
        payload["error"] = err
        payload
      end

      private def oversize?(size : Int) : Bool
        size.to_i64 > @app.max_body_size
      end

      private def send_json(payload : Hash(String, AnyData)) : Nil
        @socket.send(JsonHelper.to_string(payload))
      rescue IO::Error
        # Client already closed. Do not raise into the socket loop.
      end
    end
  end
end
