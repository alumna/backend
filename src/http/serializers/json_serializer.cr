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

      def decode(io : IO) : Hash(String, AnyData)
        parsed = JSON.parse(io)
        parsed.as_h? || {} of String => AnyData
      rescue JSON::ParseException
        {} of String => AnyData
      end
    end
  end
end
