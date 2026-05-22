require "json"

module Alumna
  module Http
    class JsonSerializer < Serializer
      def content_type : String
        "application/json"
      end

      def encode(data : Hash(String, AnyData), io : IO) : Nil
        JSON.build(io) { |builder| encode_value(data, builder) }
      end

      def encode(data : Array(Hash(String, AnyData)), io : IO) : Nil
        JSON.build(io) { |builder| encode_value(data, builder) }
      end

      private def encode_value(val, builder : JSON::Builder) : Nil
        case val
        when String then builder.scalar(val)
        when Int    then builder.scalar(val) # no .to_i64 needed
        when Float  then builder.scalar(val) # no .to_f64 needed
        when Bool   then builder.scalar(val)
        when Nil    then builder.null
        when Time
          builder.string { |io| Time::Format::RFC_3339.format(val, io, fraction_digits: 0) }
        when Bytes
          builder.array { val.each { |byte| builder.scalar(byte) } }
        when Array
          builder.array { val.each { |item| encode_value(item, builder) } }
        when Hash
          builder.object do
            val.each { |k, v| builder.field(k.to_s) { encode_value(v, builder) } }
          end
        else
          builder.null
        end
      end

      def decode(io : IO) : Hash(String, AnyData) | ServiceError
        parser = JSON::PullParser.new(io)
        result = decode_value(parser)
        unless result.is_a?(Hash(String, AnyData))
          return ServiceError.new("Request body must be a JSON object", 400)
        end
        result
      rescue JSON::ParseException
        ServiceError.new("Malformed JSON", 400)
      end

      private def decode_value(pull : JSON::PullParser) : AnyData
        case pull.kind
        when .null?   then pull.read_null
        when .bool?   then pull.read_bool
        when .int?    then pull.read_int
        when .float?  then pull.read_float
        when .string? then pull.read_string
        when .begin_array?
          ary = [] of AnyData
          pull.read_array { ary << decode_value(pull) }
          ary
        when .begin_object?
          hash = {} of String => AnyData
          pull.read_object { |key| hash[key] = decode_value(pull) }
          hash
        else
          raise JSON::ParseException.new("Unexpected token: #{pull.kind}", pull.line_number, pull.column_number)
        end
      end
    end
  end
end
