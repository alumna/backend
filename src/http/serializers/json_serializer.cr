require "json"

module Alumna
  module Http
    class JsonSerializer < Serializer
      def content_type : String
        "application/json"
      end

      def encode(data : Hash(String, AnyData), io : IO) : Nil
        io << '{'; first = true
        data.each do |k, v|
          io << ',' unless first; first = false
          k.to_json(io); io << ':'; v.to_json(io)
        end
        io << '}'
      end

      def encode(data : Array(Hash(String, AnyData)), io : IO) : Nil
        io << '['
        data.each_with_index { |h, i| io << ',' if i > 0; encode(h, io) }
        io << ']'
      end

      def decode(io : IO) : Hash(String, AnyData)
        parser = JSON::PullParser.new(io)
        value = parse_value(parser)
        case (r = value.raw)
        when Hash(String, AnyData) then r
        else
          raise ServiceError.new("Request body must be a JSON object", 400)
        end
      rescue JSON::ParseException
        raise ServiceError.new("Malformed JSON", 400)
      end

      private def parse_value(p : JSON::PullParser) : AnyData
        case p.kind
        when .null?   then AnyData.new(p.read_null)
        when .bool?   then AnyData.new(p.read_bool)
        when .int?    then AnyData.new(p.read_int)
        when .float?  then AnyData.new(p.read_float)
        when .string? then AnyData.new(p.read_string)
        when .begin_array?
          arr = [] of AnyData
          p.read_array { arr << parse_value(p) }
          AnyData.new(arr)
        when .begin_object?
          hash = {} of String => AnyData
          p.read_object { |k| hash[k] = parse_value(p) }
          AnyData.new(hash)
        else raise JSON::ParseException.new("Unexpected token", 0, 0)
        end
      end
    end
  end
end
