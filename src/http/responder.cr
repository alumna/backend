module Alumna
  module Http
    module Responder
      def self.write(response : HTTP::Server::Response, ctx : RuleContext, serializer : Serializer) : Nil
        # Always apply headers and location first — works for success and error
        ctx.http.headers.each { |k, v| response.headers[k] = v }

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
