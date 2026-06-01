# src/http/serializers/json_serializer.cr
require "json"

module Alumna
  module Http
    class JsonSerializer < Serializer
      def content_type : String
        "application/json"
      end

      def encode(data : Hash(String, AnyData), io : IO) : Nil
        JSON.build(io) { |builder| JsonHelper.encode(data, builder) }
      end

      def encode(data : Array(Hash(String, AnyData)), io : IO) : Nil
        JSON.build(io) { |builder| JsonHelper.encode(data, builder) }
      end

      def decode(io : IO) : Hash(String, AnyData) | ServiceError
        parser = JSON::PullParser.new(io)
        result = JsonHelper.decode(parser)
        unless result.is_a?(Hash(String, AnyData))
          return ServiceError.new("Request body must be a JSON object", 400)
        end
        result
      rescue JSON::ParseException
        ServiceError.new("Malformed JSON", 400)
      end
    end
  end
end
