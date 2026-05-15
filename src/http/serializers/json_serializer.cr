require "json"

module Alumna
  module Http
    class JsonSerializer < Serializer
      def content_type : String
        "application/json"
      end

      def encode(data : Hash(String, AnyData), io : IO) : Nil
        data.to_json(io)
      end

      def encode(data : Array(Hash(String, AnyData)), io : IO) : Nil
        data.to_json(io)
      end

      def decode(io : IO) : Hash(String, AnyData) | ServiceError
        parsed = JSON.parse(io)
        result = convert(parsed)

        unless result.is_a?(Hash)
          return ServiceError.new("Request body must be a JSON object", 400)
        end

        result.as(Hash(String, AnyData))
      rescue JSON::ParseException
        ServiceError.new("Malformed JSON", 400)
      end

      private def convert(value : JSON::Any) : AnyData
        case raw = value.raw
        when Hash
          raw.each_with_object({} of String => AnyData) do |(k, v), memo|
            memo[k.to_s] = convert(v)
          end
        when Array
          raw.map { |v| convert(v) }
        when Int32
          raw.to_i64
        when Int64, Float64, String, Bool, Nil
          raw
        else
          nil
        end
      end
    end
  end
end
