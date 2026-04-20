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
        peeked = io.peek
        return {} of String => AnyData if peeked.nil? || peeked.empty?

        parsed = JSON.parse(io)
        hash = parsed.as_h?
        unless hash
          raise ServiceError.new("Request body must be a JSON object", 400)
        end
        hash
      rescue JSON::ParseException
        raise ServiceError.new("Malformed JSON", 400)
      end
    end
  end
end
