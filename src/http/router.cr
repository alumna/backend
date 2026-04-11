require "http/server"

module Alumna
  module Http
    class Router
      def initialize(@app : App)
      end

      def handle(http_ctx : HTTP::Server::Context) : Nil
        request = http_ctx.request
        response = http_ctx.response

        # Input and output serializers are resolved independently
        input_serializer = resolve_input_serializer(request) || @app.serializer
        output_serializer = resolve_output_serializer(request) || input_serializer

        response.content_type = output_serializer.content_type

        match = resolve_service(request.path)
        unless match
          Responder.write_error(response, ServiceError.not_found("No service at #{request.path}"), output_serializer)
          return
        end

        service, id = match

        method = resolve_method(request.method, id)
        unless method
          Responder.write_error(response, ServiceError.new("Method not allowed", 405), output_serializer)
          return
        end

        params = parse_query(request)
        data = parse_body(request, input_serializer)
        headers = parse_headers(request)

        ctx = RuleContext.new(
          app: @app,
          service: service,
          path: service.path,
          method: method,
          phase: RulePhase::Before,
          params: params,
          headers: headers,
          id: id,
          data: data
        )

        service.dispatch(ctx)

        Responder.write(response, ctx, output_serializer)
      end

      private def resolve_service(path : String) : {Service, String?}?
        @app.services.each do |registered_path, service|
          return {service, nil} if path == registered_path

          prefix = registered_path.rstrip('/')
          if path.starts_with?(prefix + "/")
            id = path[(prefix.size + 1)..]
            return {service, id} unless id.empty? || id.includes?('/')
          end
        end

        nil
      end

      private def resolve_method(http_verb : String, id : String?) : ServiceMethod?
        has_id = !id.nil?
        case {http_verb.upcase, has_id}
        when {"GET", false}   then ServiceMethod::Find
        when {"GET", true}    then ServiceMethod::Get
        when {"POST", false}  then ServiceMethod::Create
        when {"PUT", true}    then ServiceMethod::Update
        when {"PATCH", true}  then ServiceMethod::Patch
        when {"DELETE", true} then ServiceMethod::Remove
        else                       nil
        end
      end

      private def resolve_input_serializer(request : HTTP::Request) : Serializer?
        case request.headers["content-type"]?.try(&.downcase)
        when /msgpack/ then MsgpackSerializer.new
        when /json/    then JsonSerializer.new
        end
      end

      private def resolve_output_serializer(request : HTTP::Request) : Serializer?
        case request.headers["accept"]?.try(&.downcase)
        when /msgpack/ then MsgpackSerializer.new
        when /json/    then JsonSerializer.new
        end
      end

      private def parse_query(request : HTTP::Request) : Hash(String, String)
        params = {} of String => String
        request.query_params.each { |k, v| params[k] = v }
        params
      end

      private def parse_body(request : HTTP::Request, serializer : Serializer) : Hash(String, AnyData)
        body = request.body
        return {} of String => AnyData if body.nil?
        serializer.decode(body)
      end

      private def parse_headers(request : HTTP::Request) : Hash(String, String)
        headers = {} of String => String
        request.headers.each do |name, values|
          headers[name.downcase] = values.first
        end
        headers
      end
    end
  end
end
