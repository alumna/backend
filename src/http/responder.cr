module Alumna
  module Http
    module Responder
      def self.write(response : HTTP::Server::Response, ctx : RuleContext, serializer : Serializer) : Nil
        # Apply headers only if any were set - keeps HttpOverrides lazy
        if h = ctx.http.headers?
          h.each { |k, v| response.headers[k] = v }
        end

        if location = ctx.http.location
          response.headers["Location"] = location
          response.status_code = ctx.http.status || 302
          return
        end

        if err = ctx.error
          write_error(response, err, serializer)
          return
        end

        response.status_code = ctx.http.status || default_status(ctx.method)

        # RFC 7230 sec 3.3.2 / RFC 7231 sec 6.3.5: 204 and 304 MUST NOT include a body
        return if response.status_code == 204 || response.status_code == 304

        case result = ctx.result
        when Array
          serializer.encode(result, response)
        when Hash
          serializer.encode(result, response)
        when Nil
          serializer.encode({"success" => true} of String => AnyData, response)
        end
      end

      def self.write_error(response : HTTP::Server::Response, err : ServiceError, serializer : Serializer) : Nil
        response.status_code = err.status
        payload = {
          "error"   => err.message || "Error",
          "details" => err.details,
        } of String => AnyData
        serializer.encode(payload, response)
      end

      private def self.default_status(method : ServiceMethod) : Int32
        method.create? ? 201 : 200
      end
    end
  end
end
